#!/usr/bin/env bash

set -xeuo pipefail

# The hyperscale SIG's kernel straight from their official builds

dnf -y install centos-release-hyperscale-kernel
dnf config-manager --set-disabled "centos-hyperscale,centos-hyperscale-kernel"
dnf versionlock delete kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-uki-virt
dnf --enablerepo="centos-hyperscale" --enablerepo="centos-hyperscale-kernel" -y update kernel
dnf versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-uki-virt

# Only necessary when not building with Nvidia
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//' | tail -n 1)"
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
