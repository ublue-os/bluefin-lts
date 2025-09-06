#!/bin/bash
set ${CI:+-x} -euo pipefail

# /*
# Get Kernel Version
# */
KERNEL_SUFFIX=""
KERNEL_NAME="kernel"
KERNEL_VRA="$(rpm -q "$KERNEL_NAME" --queryformat '%{EVR}.%{ARCH}')"
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//' | tail -n 1)"

# /*
### install base server ZFS packages and sanoid dependencies
# */
dnf -y install \
    /tmp/akmods-zfs-rpms/kmods/zfs/kmod-zfs-"${KERNEL_VRA}"-*.rpm \
    /tmp/akmods-zfs-rpms/kmods/zfs/libnvpair3-*.rpm \
    /tmp/akmods-zfs-rpms/kmods/zfs/libuutil3-*.rpm \
    /tmp/akmods-zfs-rpms/kmods/zfs/libzfs6-*.rpm \
    /tmp/akmods-zfs-rpms/kmods/zfs/libzpool6-*.rpm \
    /tmp/akmods-zfs-rpms/kmods/zfs/python3-pyzfs-*.rpm \
    /tmp/akmods-zfs-rpms/kmods/zfs/zfs-*.rpm

# /*
# depmod ran automatically with zfs 2.1 but not with 2.2
# */
depmod -a "${KERNEL_VRA}"

/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
