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
  # For HWE mode, download kernel and akmods from ublue-os/bluefin's akmods repo
  # This uses the same approach as ublue-os/bluefin for consistency
  
  # Determine the latest kernel version from ublue-os/akmods
  # For CentOS Stream 10, we use fedora 40 akmods as the closest match
  AKMODS_FLAVOR="coreos-stable"
  FEDORA_VERSION="40"
  
  # Try to get the latest kernel tag, fallback to a known stable version
  KERNEL_VERSION=$(skopeo list-tags docker://ghcr.io/ublue-os/akmods 2>/dev/null | \
    jq -r '.Tags[]' | \
    grep "^${AKMODS_FLAVOR}-${FEDORA_VERSION}" | \
    sort -V | tail -1 | \
    sed "s/${AKMODS_FLAVOR}-${FEDORA_VERSION}-//") || KERNEL_VERSION="6.11.5-200.fc40.x86_64"
  
  echo "Using kernel version: ${KERNEL_VERSION}"
  
  # Fetch Common AKMODS & Kernel RPMS from ublue-os
  skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods:"${AKMODS_FLAVOR}"-"${FEDORA_VERSION}"-"${KERNEL_VERSION}" dir:/tmp/hwe-akmods
  AKMODS_TARGZ=$(jq -r '.layers[].digest' </tmp/hwe-akmods/manifest.json | cut -d : -f 2)
  tar -xvzf /tmp/hwe-akmods/"$AKMODS_TARGZ" -C /tmp/
  
  # kernel-rpms directory should be extracted to /tmp/kernel-rpms
  # Install the downloaded kernel
  INSTALL_PKGS=( "${KERNEL_NAME}" "${KERNEL_NAME}-core" "${KERNEL_NAME}-modules" "${KERNEL_NAME}-devel" "${KERNEL_NAME}-devel-matched" )
  
  RPM_NAMES=()
  for pkg in "${INSTALL_PKGS[@]}"; do
    rpm_file=$(find /tmp/kernel-rpms -name "$pkg-*.rpm" -type f | head -1)
    if [[ -n "$rpm_file" ]]; then
      RPM_NAMES+=("$rpm_file")
    fi
  done
  
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