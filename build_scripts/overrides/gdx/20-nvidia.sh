#!/bin/bash
set ${CI:+-x} -euo pipefail

# /*
# Get Kernel Version
# */
KERNEL_NAME="kernel"
KERNEL_VRA="$(rpm -q "$KERNEL_NAME" --queryformat '%{EVR}.%{ARCH}')"
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//' | tail -n 1)"

dnf config-manager --add-repo="https://negativo17.org/repos/epel-nvidia.repo"
dnf config-manager --set-disabled "epel-nvidia"

### install Nvidia driver packages and dependencies
# */
dnf -y install --enablerepo="epel-nvidia"\
    /tmp/akmods-nvidia-open-rpms/kmods/kmod-nvidia-"${KERNEL_VRA}"-*.rpm \
    /tmp/akmods-nvidia-open-rpms/ublue-os/*.rpm

# enable repos provided by ublue-os-nvidia-addons
dnf config-manager --set-enabled "nvidia-container-toolkit"

dnf install -y --enablerepo="epel-nvidia" --enablerepo="epel" \
    libnvidia-fbc \
    nvidia-driver \
    nvidia-driver-cuda \
    nvidia-settings \
    nvidia-container-toolkit

# Ensure the version of the Nvidia module matches the driver
KMOD_VERSION="$(rpm -q --queryformat '%{VERSION}' kmod-nvidia)"
DRIVER_VERSION="$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"
if [ "$KMOD_VERSION" != "$DRIVER_VERSION" ]; then
    echo "Error: kmod-nvidia version ($KMOD_VERSION) does not match nvidia-driver version ($DRIVER_VERSION)"
    exit 1
fi

sed -i -e 's/kernel$/kernel-open/g' /etc/nvidia/kernel.conf
cat /etc/nvidia/kernel.conf

cat >/usr/lib/modprobe.d/00-nouveau-blacklist.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

cat >/usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

## nvidia post-install steps
# disable repos provided by ublue-os-nvidia-addons
dnf config-manager --set-disabled nvidia-container-toolkit

systemctl enable ublue-nvctk-cdi.service
semodule --verbose --install /usr/share/selinux/packages/nvidia-container.pp

# Universal Blue specific Initramfs fixes
cp /etc/modprobe.d/nvidia-modeset.conf /usr/lib/modprobe.d/nvidia-modeset.conf
# we must force driver load to fix black screen on boot for nvidia desktops
sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
# as we need forced load, also mustpre-load intel/amd iGPU else chromium web browsers fail to use hardware acceleration
sed -i 's@ nvidia @ i915 amdgpu nvidia @g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf

# Make sure initramfs is rebuilt after nvidia drivers or kernel replacement
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"