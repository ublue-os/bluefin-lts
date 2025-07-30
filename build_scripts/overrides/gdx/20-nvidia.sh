#!/usr/bin/env bash

set -euox pipefail

KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//' | tail -n 1)"

dnf config-manager --add-repo="https://negativo17.org/repos/epel-nvidia.repo"
dnf config-manager --set-disabled "epel-nvidia"

# These are necessary for building the nvidia drivers
# Also make sure the kernel is locked before this is run whenever the kernel updates
# kernel-devel might pull in an entire new kernel if you dont do
dnf versionlock delete kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-uki-virt
if [ "${ENABLE_HWE}" == "1" ] ; then
dnf -y --enablerepo="centos-kmods-kernel" install "kernel-devel-$QUALIFIED_KERNEL" "kernel-headers-$QUALIFIED_KERNEL"  dkms gcc-c++
else
dnf -y install "kernel-devel-$QUALIFIED_KERNEL" "kernel-headers-$QUALIFIED_KERNEL"  dkms gcc-c++
fi
dnf versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-uki-virt


dnf install -y --enablerepo="epel-nvidia" \
  nvidia-driver{,-cuda} dkms-nvidia

sed -i -e 's/kernel$/kernel-open/g' /etc/nvidia/kernel.conf
cat /etc/nvidia/kernel.conf

# The nvidia-open driver tries to use the kernel from the host. (uname -r), just override it and let it do whatever otherwise
# FIXME: remove this workaround please at some point
cat >/tmp/fake-uname <<EOF
#!/usr/bin/env bash

if [ "\$1" == "-r" ] ; then
  echo ${QUALIFIED_KERNEL}
  exit 0
fi

exec /usr/bin/uname \$@
EOF
install -Dm0755 /tmp/fake-uname /tmp/bin/uname

NVIDIA_DRIVER_VERSION="$(rpm -q dkms-nvidia --queryformat="%{VERSION}")"
PATH=/tmp/bin:$PATH dkms --force install -m nvidia -v $NVIDIA_DRIVER_VERSION -k "$QUALIFIED_KERNEL"
cat "/var/lib/dkms/nvidia/$NVIDIA_DRIVER_VERSION/build/make.log" || echo "Expected failure"

cat >/usr/lib/modprobe.d/00-nouveau-blacklist.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

cat >/usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

# Make sure initramfs is rebuilt after nvidia drivers or kernel replacement
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v -f
