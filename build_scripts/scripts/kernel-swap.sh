#!/bin/bash
# /*
#shellcheck disable=SC1083
# */

set ${CI:+-x} -euo pipefail

# /*
### Kernel Swap - Install kernel from mounted akmods containers
### Containerfile provides the correct kernel via AKMODS_VERSION:
###   - centos-10 for standard builds
###   - coreos-stable-42 for HWE builds
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

# HWE-specific: Install common akmods
# These are not in the base mounts, so we download them via skopeo
if [[ "${ENABLE_HWE:-0}" -eq "1" ]]; then
  echo "HWE mode enabled - installing common akmods..."
  
  # Detect kernel version from installed kernel
  KERNEL_VERSION=$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')
  echo "Detected kernel version: ${KERNEL_VERSION}"
  
  # Use the same akmods flavor and Fedora version as coreos-stable-42
  AKMODS_FLAVOR="coreos-stable"
  FEDORA_VERSION="42"
  
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
    ls -lh "$COMMON_AKMODS_DIR"/rpms/ || true
    ls -lh "$COMMON_AKMODS_DIR"/rpms/kmods/ || true
    
    echo "Installing common akmods with dependencies..."
    # Install both the -kmod-common packages (from rpms/) and kmod-* packages (from rpms/kmods/)
    dnf -y install \
      "$COMMON_AKMODS_DIR"/rpms/*xone*.rpm \
      "$COMMON_AKMODS_DIR"/rpms/*openrazer*.rpm \
      "$COMMON_AKMODS_DIR"/rpms/*framework-laptop*.rpm \
      "$COMMON_AKMODS_DIR"/rpms/*v4l2loopback*.rpm \
      "$COMMON_AKMODS_DIR"/rpms/kmods/*xone*.rpm \
      "$COMMON_AKMODS_DIR"/rpms/kmods/*openrazer*.rpm \
      "$COMMON_AKMODS_DIR"/rpms/kmods/*framework-laptop*.rpm \
      "$COMMON_AKMODS_DIR"/rpms/kmods/*v4l2loopback*.rpm \
      || echo "Warning: Some common akmods failed to install (non-critical)"
  else
    echo "Warning: No rpms directory found in common akmods container"
  fi
  echo "Installed common akmods packages:"
  rpm -qa | grep -E 'xone|openrazer|framework|v4l2loopback' || true
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