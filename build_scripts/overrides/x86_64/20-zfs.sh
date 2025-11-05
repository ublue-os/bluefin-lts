#!/bin/bash
set ${CI:+-x} -euo pipefail

# /*
# Get Kernel Version
# */
KERNEL_SUFFIX=""
KERNEL_NAME="kernel"
KERNEL_VRA="$(rpm -q "$KERNEL_NAME" --queryformat '%{EVR}.%{ARCH}')"
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//' | tail -n 1)"

# Determine akmods path based on HWE mode
# Works for all architectures since KERNEL_VRA includes arch
if [[ "${ENABLE_HWE:-0}" -eq "1" ]]; then
  AKMODS_ZFS_PATH="/run/hwe-download/akmods-zfs-rpms"
else
  AKMODS_ZFS_PATH="/tmp/akmods-zfs-rpms"
fi

# /*
### install base server ZFS packages and sanoid dependencies
# */
dnf -y install \
    "$AKMODS_ZFS_PATH"/kmods/zfs/kmod-zfs-"${KERNEL_VRA}"-*.rpm \
    "$AKMODS_ZFS_PATH"/kmods/zfs/libnvpair3-*.rpm \
    "$AKMODS_ZFS_PATH"/kmods/zfs/libuutil3-*.rpm \
    "$AKMODS_ZFS_PATH"/kmods/zfs/libzfs6-*.rpm \
    "$AKMODS_ZFS_PATH"/kmods/zfs/libzpool6-*.rpm \
    "$AKMODS_ZFS_PATH"/kmods/zfs/zfs-*.rpm \
    pv

# python3-pyzfs requires python3.13dist(cffi) which is not available in CentOS Stream 10
# Install it separately if the package exists and dependencies can be resolved
dnf -y install --skip-broken "$AKMODS_ZFS_PATH"/kmods/zfs/python3-pyzfs-*.rpm || true

# /*
# depmod ran automatically with zfs 2.1 but not with 2.2
# */
depmod -a "${KERNEL_VRA}"

# Autoload ZFS module
echo "zfs" >/usr/lib/modules-load.d/zfs.conf

/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
