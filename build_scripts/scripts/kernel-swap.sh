#!/bin/bash
# /*
#shellcheck disable=SC1083
# */

set ${CI:+-x} -euo pipefail

# /*
### Kernel Swap to Kernel signed with our MOK
# */

KERNEL_NAME="kernel"

# Remove existing kernel packages
# always remove these packages as kernel cache provides signed versions of kernel or kernel-longterm
PKGS=( "${KERNEL_NAME}" "${KERNEL_NAME}-core" "${KERNEL_NAME}-modules" "${KERNEL_NAME}-modules-core" "${KERNEL_NAME}-modules-extra" "${KERNEL_NAME}-uki-virt" )
for pkg in "${PKGS[@]}"; do
  rpm --erase "$pkg" --nodeps || true
done

if [[ "$ENABLE_HWE" -eq "1" ]]; then
  # For HWE mode, use the same Fedora kernel and akmods as ublue-os/bluefin
  # This provides better hardware support and compatibility
  
  # Use the same akmods flavor and Fedora version as bluefin stable
  AKMODS_FLAVOR="coreos-stable"
  FEDORA_VERSION="42"
  
  # Get the latest kernel version from ublue-os/akmods using the ostree.linux label
  # This matches exactly how bluefin determines the kernel version
  echo "Detecting latest Fedora ${FEDORA_VERSION} kernel from ublue-os/akmods..."
  KERNEL_VERSION=$(skopeo inspect --retry-times 3 docker://ghcr.io/ublue-os/akmods:"${AKMODS_FLAVOR}"-"${FEDORA_VERSION}" | \
    jq -r '.Labels["ostree.linux"]')
  
  if [[ -z "$KERNEL_VERSION" || "$KERNEL_VERSION" == "null" ]]; then
    echo "ERROR: Failed to detect kernel version from akmods container"
    exit 1
  fi
  
  echo "Using Fedora kernel version: ${KERNEL_VERSION}"
  
  # Fetch Common AKMODS & Kernel RPMS from ublue-os (Fedora packages)
  echo "Downloading akmods:${AKMODS_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION}..."
  skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods:"${AKMODS_FLAVOR}"-"${FEDORA_VERSION}"-"${KERNEL_VERSION}" dir:/tmp/hwe-akmods
  AKMODS_TARGZ=$(jq -r '.layers[].digest' </tmp/hwe-akmods/manifest.json | cut -d : -f 2)
  tar -xvzf /tmp/hwe-akmods/"$AKMODS_TARGZ" -C /tmp/
  
  # Fetch ZFS akmods for HWE (Fedora packages)
  echo "Downloading akmods-zfs:${AKMODS_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION}..."
  skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods-zfs:"${AKMODS_FLAVOR}"-"${FEDORA_VERSION}"-"${KERNEL_VERSION}" dir:/tmp/hwe-akmods-zfs
  ZFS_TARGZ=$(jq -r '.layers[].digest' </tmp/hwe-akmods-zfs/manifest.json | cut -d : -f 2)
  tar -xvzf /tmp/hwe-akmods-zfs/"$ZFS_TARGZ" -C /tmp/
  # Move to expected location for override scripts
  mkdir -p /tmp/akmods-zfs-rpms
  if [[ -d /tmp/rpms ]]; then
    mv /tmp/rpms/* /tmp/akmods-zfs-rpms/ 2>/dev/null || true
  fi
  
  # Fetch Nvidia Open akmods for HWE (Fedora packages)
  echo "Downloading akmods-nvidia-open:${AKMODS_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION}..."
  skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods-nvidia-open:"${AKMODS_FLAVOR}"-"${FEDORA_VERSION}"-"${KERNEL_VERSION}" dir:/tmp/hwe-akmods-nvidia
  NVIDIA_TARGZ=$(jq -r '.layers[].digest' </tmp/hwe-akmods-nvidia/manifest.json | cut -d : -f 2)
  tar -xvzf /tmp/hwe-akmods-nvidia/"$NVIDIA_TARGZ" -C /tmp/
  # Move to expected location for override scripts
  mkdir -p /tmp/akmods-nvidia-open-rpms
  if [[ -d /tmp/rpms ]]; then
    mv /tmp/rpms/* /tmp/akmods-nvidia-open-rpms/ 2>/dev/null || true
  fi
  
  # kernel-rpms directory should be extracted to /tmp/kernel-rpms
  # Install the downloaded Fedora kernel packages
  INSTALL_PKGS=( "${KERNEL_NAME}" "${KERNEL_NAME}-core" "${KERNEL_NAME}-modules" "${KERNEL_NAME}-devel" "${KERNEL_NAME}-devel-matched" )
  
  RPM_NAMES=()
  for pkg in "${INSTALL_PKGS[@]}"; do
    rpm_file=$(find /tmp/kernel-rpms -name "$pkg-*.rpm" -type f | head -1)
    if [[ -n "$rpm_file" ]]; then
      RPM_NAMES+=("$rpm_file")
    fi
  done
  
  if [[ ${#RPM_NAMES[@]} -eq 0 ]]; then
    echo "ERROR: No kernel RPMs found in /tmp/kernel-rpms"
    exit 1
  fi
  
  dnf -y install "${RPM_NAMES[@]}"
else
  # For non-HWE mode, use the kernel from the mounted akmods containers
  find /tmp/kernel-rpms

  pushd /tmp/kernel-rpms
  CACHED_VERSION=$(find $KERNEL_NAME-*.rpm | grep -P "$KERNEL_NAME-\d+\.\d+\.\d+-\d+$(rpm -E %{dist})" | sed -E "s/$KERNEL_NAME-//;s/\.rpm//")
  popd

  INSTALL_PKGS=( "${KERNEL_NAME}" "${KERNEL_NAME}-core" "${KERNEL_NAME}-modules" "${KERNEL_NAME}-modules-core" "${KERNEL_NAME}-modules-extra" "${KERNEL_NAME}-uki-virt" "${KERNEL_NAME}-devel" "${KERNEL_NAME}-devel-matched" )

  RPM_NAMES=()
  for pkg in "${INSTALL_PKGS[@]}"; do
    RPM_NAMES+=("/tmp/kernel-rpms/$pkg-$CACHED_VERSION.rpm")
  done

  dnf -y install "${RPM_NAMES[@]}"
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