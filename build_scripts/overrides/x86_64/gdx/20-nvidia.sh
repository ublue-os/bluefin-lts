#!/usr/bin/env bash

set -euox pipefail

# FIXME: add renovate rules for this (somehow?)
NVIDIA_DISTRO="rhel9"

# These are necessary for building the nvidia drivers
# DKMS is provided by EPEL
# Also make sure the kernel is locked before this is run whenever the kernel updates
# kernel-devel might pull in an entire new kernel
dnf -y install kernel-devel kernel-devel-matched kernel-headers dkms

dnf config-manager --add-repo "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_DISTRO}/$(arch)/cuda-${NVIDIA_DISTRO}.repo"
dnf clean expire-cache
NVIDIA_DRIVER_DIRECTORY=$(mktemp -d)

# EGL-gbm and EGL-wayland fail to install because of conflicts with each other
dnf download egl-gbm egl-wayland --destdir=$NVIDIA_DRIVER_DIRECTORY
rpm -ivh $NVIDIA_DRIVER_DIRECTORY/*.rpm --nodeps --force

dnf -y install --nogpgcheck \
  -x egl-wayland \
  -x egl-gbm \
  nvidia-driver{,-cuda} kmod-nvidia-open-dkms

cat >/usr/lib/modprobe.d/00-nouveau-blacklist.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

cat >/usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
match-architectures = ["x86_64"]
EOF


# Make sure initramfs is rebuilt after nvidia drivers or kernel replacement
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v -f
