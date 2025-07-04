set -euo pipefail

# /*
# Get Kernel Version
# */
KERNEL_VRA="$(rpm -q kernel --queryformat '%{EVR}.%{ARCH}')"

# /*
### install base server ZFS packages and sanoid dependencies
# */
dnf -y install \
    pv \
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
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v -f

