#!/usr/bin/env bash

set -euox pipefail

dnf config-manager --add-repo="https://negativo17.org/repos/epel-nvidia.repo"
dnf config-manager --set-disabled "epel-nvidia"

# These are necessary for building the nvidia drivers
# DKMS is provided by EPEL
# Also make sure the kernel is locked before this is run whenever the kernel updates
# kernel-devel might pull in an entire new kernel if you dont do
dnf versionlock delete kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-uki-virt
dnf -y update kernel
dnf -y install kernel-devel kernel-devel-matched kernel-headers dkms gcc-c++
dnf versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-uki-virt

NVIDIA_DRIVER_VERSION="$(dnf repoquery --disablerepo="*" --enablerepo="epel-nvidia" --queryformat "%{VERSION}-%{RELEASE}" kmod-nvidia --quiet)"
# Workaround for `kmod-nvidia` package not getting downloaded properly off of negativo's repos
# FIXME: REMOVE THIS at some point. (added 24-02-2025)
NEGATIVO_RPM="$(mktemp --suffix .rpm)"
curl --retry 3 -Lo $NEGATIVO_RPM "https://negativo17.org/repos/nvidia/epel-${MAJOR_VERSION_NUMBER}/$(arch)/kmod-nvidia-${NVIDIA_DRIVER_VERSION}.$(arch).rpm"
dnf install -y --enablerepo="epel-nvidia" $NEGATIVO_RPM

dnf install -y --enablerepo="epel-nvidia" \
  cuda nvidia-driver{,-cuda}

sed -i -e 's/kernel$/kernel-open/g' /etc/nvidia/kernel.conf
cat /etc/nvidia/kernel.conf

# The nvidia-open driver tries to use the kernel from the host. (uname -r), just override it and let it do whatever otherwise
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"

cat >/tmp/fake-uname <<EOF
#!/usr/bin/env bash

if [ "\$1" == "-r" ] ; then
  echo ${QUALIFIED_KERNEL}
  exit 0
fi

exec /usr/bin/uname \$@
EOF
install -Dm0755 /tmp/fake-uname /tmp/bin/uname

# PATH modification for fake-uname
PATH=/tmp/bin:$PATH akmods --kernels "$QUALIFIED_KERNEL" --rebuild
cat " /var/cache/akmods/nvidia/${NVIDIA_DRIVER_VERSION}-for-${QUALIFIED_KERNEL}.failed.log" || echo "Expected failure"

cat >/usr/lib/modprobe.d/00-nouveau-blacklist.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

cat >/usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

# Make sure initramfs is rebuilt after nvidia drivers or kernel replacement
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v -f
