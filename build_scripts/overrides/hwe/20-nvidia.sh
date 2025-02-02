#!/usr/bin/env bash

set -euox pipefail

# FIXME: add renovate rules for this
NVIDIA_VERSION="570"
NVIDIA_DISTRO="rhel9"

# kernel-devel, kernel-devel-matched and kernel-headers are necessary for nvidia drivers
dnf --enablerepo="centos-hyperscale" --enablerepo="centos-hyperscale-kernel" -y install kernel-devel kernel-devel-matched kernel-headers

dnf config-manager --add-repo "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_DISTRO}/$(arch)/cuda-${NVIDIA_DISTRO}.repo"
dnf clean expire-cache
NVIDIA_DRIVER_DIRECTORY=$(mktemp -d)

# Make sure hyperscale repos are enabled for kernel dependencies
dnf config-manager --set-enabled "centos-hyperscale"
dnf config-manager --set-enabled "centos-hyperscale-kernel"

# EGL-gbm and EGL-wayland fail to install because of conflicts with each other
dnf download egl-gbm egl-wayland --destdir=$NVIDIA_DRIVER_DIRECTORY
rpm -ivh $NVIDIA_DRIVER_DIRECTORY/*.rpm --nodeps --force
dnf -y install --nogpgcheck \
  -x egl-wayland \
  -x egl-gbm \
  nvidia-driver kmod-nvidia-open-dkms
echo "blacklist nouveau" | tee /etc/modprobe.d/nouveau-blacklist.conf
echo "options nouveau modeset=0" | tee -a /etc/modprobe.d/nouveau-blacklist.conf

dnf config-manager --set-disabled "centos-hyperscale"
dnf config-manager --set-disabled "centos-hyperscale-kernel"

# Make sure initramfs is rebuilt after nvidia drivers or kernel replacement
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v -f
