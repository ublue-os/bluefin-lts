#!/bin/bash
# /*
#shellcheck disable=SC1083
# */

set ${CI:+-x} -euo pipefail

# /*
### Kernel Swap to Kernel signed with our MOK
# */

find /tmp/kernel-rpms

pushd /tmp/kernel-rpms
KERNEL_NAME="kernel"
CACHED_VERSION=$(find $KERNEL_NAME-*.rpm | grep -P "$KERNEL_NAME-\d+\.\d+\.\d+-\d+$(rpm -E %{dist})" | sed -E "s/$KERNEL_NAME-//;s/\.rpm//")
popd

# /*
# always remove these packages as kernel cache provides signed versions of kernel or kernel-longterm
# */
PKGS=( "${KERNEL_NAME}" "${KERNEL_NAME}-core" "${KERNEL_NAME}-modules" "${KERNEL_NAME}-modules-core" "${KERNEL_NAME}-modules-extra" "${KERNEL_NAME}-uki-virt" )
for pkg in "${PKGS[@]}"; do
  rpm --erase $pkg --nodeps || true
done

if [[ "$ENABLE_HWE" -eq "1" ]]; then
  export PKGS=( "${KERNEL_NAME}" "${KERNEL_NAME}-core" "${KERNEL_NAME}-modules" )
fi

PKGS+=("${KERNEL_NAME}-devel" "${KERNEL_NAME}-devel-matched")

RPM_NAMES=()
for pkg in "${PKGS[@]}"; do
  RPM_NAMES+=("/tmp/kernel-rpms/$pkg-$CACHED_VERSION.rpm")
done

dnf -y install "${RPM_NAMES[@]}"

# /*
### Version Lock kernel packages
# */
dnf versionlock add \
  "$KERNEL_NAME" \
  "$KERNEL_NAME"-core \
  "$KERNEL_NAME"-modules \
  "$KERNEL_NAME"-modules-core \
  "$KERNEL_NAME"-modules-extra