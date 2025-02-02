#!/usr/bin/env bash

set -euox pipefail

# The hyperscale SIG's kernel straight from their official builds
dnf -y install centos-release-hyperscale-kernel
dnf config-manager --set-disabled "centos-hyperscale"
dnf config-manager --set-disabled "centos-hyperscale-kernel"
dnf --enablerepo="centos-hyperscale" --enablerepo="centos-hyperscale-kernel" -y update kernel

# Only necessary when not building with Nvidia
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v -f
