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
# The kmod matches the installed kernel (centos-10 or coreos-stable akmods).
# The userspace always comes from the centos-10 akmods: the coreos-stable one
# is a Fedora build and can link libraries CentOS doesn't have (OpenSSL 4 on F45).
# */
ZFS_USERSPACE_RPMS="/tmp/akmods-zfs-userspace-rpms/kmods/zfs"
dnf -y install \
    /tmp/akmods-zfs-rpms/kmods/zfs/kmod-zfs-"${KERNEL_VRA}"-*.rpm \
    "${ZFS_USERSPACE_RPMS}"/libnvpair3-*.rpm \
    "${ZFS_USERSPACE_RPMS}"/libuutil3-*.rpm \
    "${ZFS_USERSPACE_RPMS}"/libzfs7-*.rpm \
    "${ZFS_USERSPACE_RPMS}"/libzpool7-*.rpm \
    "${ZFS_USERSPACE_RPMS}"/zfs-*.rpm \
    

  # python3-pyzfs requires python3.13dist(cffi) which is not available in CentOS Stream 10
  # Install it separately if the package exists and dependencies can be resolved
  dnf -y install --skip-broken "${ZFS_USERSPACE_RPMS}"/python3-pyzfs-*.rpm || true

# The kmod and the userspace come from two akmods images. Fail the build if
# their ZFS versions ever differ.
ZFS_KMOD_VERSION="$(rpm -q --queryformat '%{VERSION}' kmod-zfs)"
for pkg in zfs libzfs7 libzpool7 libnvpair3 libuutil3; do
    pkg_version="$(rpm -q --queryformat '%{VERSION}' "${pkg}")"
    if [[ "${pkg_version}" != "${ZFS_KMOD_VERSION}" ]]; then
        echo "FATAL: ${pkg} ${pkg_version} does not match kmod-zfs ${ZFS_KMOD_VERSION}"
        exit 1
    fi
done

# /*
# depmod ran automatically with zfs 2.1 but not with 2.2
# */
depmod -a "${KERNEL_VRA}"

# Autoload ZFS module
echo "zfs" >/usr/lib/modules-load.d/zfs.conf

/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --tmpdir /boot --zstd -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
