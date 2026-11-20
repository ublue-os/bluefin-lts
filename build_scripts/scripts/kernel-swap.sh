#!/bin/bash
# /*
#shellcheck disable=SC1083
# */

set ${CI:+-x} -euo pipefail

# /*
### Kernel Swap - Install kernel from mounted akmods containers
### Containerfile provides the correct kernel via AKMODS_VERSION:
###   - centos-10 for standard builds
###   - coreos-stable-<COREOS_STABLE_VERSION> for HWE/GDX builds (see Justfile)
# */

KERNEL_NAME="kernel"

# Remove existing kernel packages
# Always remove these packages as kernel cache provides signed versions
PKGS=( "${KERNEL_NAME}" "${KERNEL_NAME}-core" "${KERNEL_NAME}-modules" "${KERNEL_NAME}-modules-core" "${KERNEL_NAME}-modules-extra" "${KERNEL_NAME}-uki-virt" )
for pkg in "${PKGS[@]}"; do
  rpm --erase "$pkg" --nodeps || true
done

# Install kernel from mounted /tmp/kernel-rpms (provided by Containerfile akmods mounts)
echo "Installing kernel from mounted kernel-rpms..."
find /tmp/kernel-rpms

# Extract version from the first kernel rpm filename (handles both .el10 and .fc42 dist tags)
CACHED_VERSION=$(cd /tmp/kernel-rpms && ls kernel-[0-9]*.rpm 2>/dev/null | head -1 | sed -E 's/^kernel-//;s/\.rpm$//')

if [[ -z "$CACHED_VERSION" ]]; then
  echo "ERROR: Could not detect kernel version from /tmp/kernel-rpms"
  ls -la /tmp/kernel-rpms/
  exit 1
fi

echo "Detected kernel version: ${CACHED_VERSION}"

INSTALL_PKGS=( "${KERNEL_NAME}" "${KERNEL_NAME}-core" "${KERNEL_NAME}-modules" "${KERNEL_NAME}-modules-core" "${KERNEL_NAME}-modules-extra" "${KERNEL_NAME}-uki-virt" "${KERNEL_NAME}-devel" "${KERNEL_NAME}-devel-matched" )

RPM_NAMES=()
for pkg in "${INSTALL_PKGS[@]}"; do
  RPM_NAMES+=("/tmp/kernel-rpms/$pkg-$CACHED_VERSION.rpm")
done

dnf -y install "${RPM_NAMES[@]}"

# Fedora kernels (HWE/GDX) are built with CONFIG_MODPROBE_PATH="/usr/bin/modprobe",
# because Fedora merged /usr/sbin into /usr/bin. CentOS Stream 10 only ships
# /usr/sbin/modprobe, so without this every kernel-side module autoload
# (request_module) fails silently: dm-crypt on LUKS boots, filesystems,
# nftables, crypto. udev loads still work because they use libkmod directly.
# Create the path the kernel expects. This runs before any dracut call, so the
# link also lands in the initramfs. No-op for the CentOS kernel.
KERNEL_MODPROBE_PATH="$(sed -n 's/^CONFIG_MODPROBE_PATH="\(.*\)"$/\1/p' "/usr/lib/modules/${CACHED_VERSION}/config")"
if [[ -n "${KERNEL_MODPROBE_PATH}" && ! -e "${KERNEL_MODPROBE_PATH}" ]]; then
  echo "Kernel expects modprobe at ${KERNEL_MODPROBE_PATH}; linking it to /usr/bin/kmod"
  ln -sr /usr/bin/kmod "${KERNEL_MODPROBE_PATH}"
fi

# HWE-specific: Install common akmods
# These are not in the base mounts, so we download them via skopeo
if [[ "${ENABLE_HWE:-0}" -eq 1 || "${ENABLE_GDX:-0}" -eq 1 ]]; then
  echo "HWE mode enabled - installing common akmods..."
  
  # Detect kernel version from installed kernel
  KERNEL_VERSION=$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')
  echo "Detected kernel version: ${KERNEL_VERSION}"
  
  # Use the same akmods flavor and Fedora version as the mounted coreos-stable
  # kernel. Take the Fedora version from the kernel's dist tag (e.g. fc44) so the
  # Justfile's coreos_stable_version is the only place to bump.
  AKMODS_FLAVOR="coreos-stable"
  FEDORA_VERSION="$(sed -nE 's/.*\.fc([0-9]+)\..*/\1/p' <<<"${KERNEL_VERSION}")"
  if [[ -z "${FEDORA_VERSION}" ]]; then
    echo "ERROR: Could not read the Fedora version from kernel ${KERNEL_VERSION}"
    exit 1
  fi
  
  # Create writable directory for common akmods downloads (tmpfs /tmp is mounted)
  COMMON_AKMODS_DIR="/run/common-akmods"
  mkdir -p "$COMMON_AKMODS_DIR"
  
  # Fetch common akmods container for the kernel version
  echo "Downloading common akmods for kernel ${KERNEL_VERSION}..."
  skopeo copy --retry-times 3 \
    docker://ghcr.io/ublue-os/akmods:"${AKMODS_FLAVOR}"-"${FEDORA_VERSION}"-"${KERNEL_VERSION}" \
    dir:"$COMMON_AKMODS_DIR"/akmods-container
  
  # Extract the common akmods rpms
  AKMODS_TARGZ=$(jq -r '.layers[].digest' <"$COMMON_AKMODS_DIR"/akmods-container/manifest.json | cut -d : -f 2)
  tar -xzf "$COMMON_AKMODS_DIR"/akmods-container/"$AKMODS_TARGZ" -C "$COMMON_AKMODS_DIR"
  
  # Install common akmods if they exist
  if [[ -d "$COMMON_AKMODS_DIR"/rpms ]]; then
    echo "Available common akmods packages:"
    ls -lh "$COMMON_AKMODS_DIR"/rpms/common/ || true
    ls -lh "$COMMON_AKMODS_DIR"/rpms/kmods/ || true
    
    # akmods ships each kmod-<name> in rpms/kmods/ and its userspace or
    # -kmod-common package in rpms/common/. Not every kmod is built for every
    # arch (openrazer has no aarch64 build), so collect only the ones that exist.
    # Without nullglob a pattern that matches nothing reaches dnf as a literal
    # path and dnf drops the whole transaction.
    COMMON_AKMODS_RPMS=()
    shopt -s nullglob
    for kmod in xone openrazer v4l2loopback; do
      kmod_rpms=("$COMMON_AKMODS_DIR"/rpms/kmods/kmod-"${kmod}"-*.rpm)
      if [[ ${#kmod_rpms[@]} -eq 0 ]]; then
        echo "Skipping ${kmod}: not built for $(uname -m) in the akmods image"
        continue
      fi
      COMMON_AKMODS_RPMS+=("${kmod_rpms[@]}" "$COMMON_AKMODS_DIR"/rpms/common/*"${kmod}"*.rpm)
    done
    shopt -u nullglob
    
    # A real dnf error fails the build. 26-packages-post.sh checks the modules.
    if [[ ${#COMMON_AKMODS_RPMS[@]} -gt 0 ]]; then
      echo "Installing common akmods with dependencies..."
      dnf -y install "${COMMON_AKMODS_RPMS[@]}"
    fi
  else
    echo "Warning: No rpms directory found in common akmods container"
  fi
  echo "Installed common akmods packages:"
  rpm -qa | grep -E 'xone|openrazer|v4l2loopback' || true
  # Cleanup
  rm -rf "$COMMON_AKMODS_DIR"
else
  echo "Standard mode - common akmods not installed"
fi

# /*
### Version Lock kernel packages
# */
dnf versionlock add \
  "$KERNEL_NAME" \
  "$KERNEL_NAME"-core \
  "$KERNEL_NAME"-modules \
  "$KERNEL_NAME"-modules-core \
  "$KERNEL_NAME"-modules-extra

# Add akmods secureboot key
mkdir -p /etc/pki/akmods/certs
curl --retry 15 -Lo /etc/pki/akmods/certs/akmods-ublue.der "https://github.com/ublue-os/akmods/raw/main/certs/public_key.der"
