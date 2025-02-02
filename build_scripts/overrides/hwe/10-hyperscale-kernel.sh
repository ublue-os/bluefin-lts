#!/usr/bin/env bash

set -euox pipefail

# The hyperscale SIG's kernel straight from Koji builds because they dont seem to have published it to their repos yet.

KERNEL_PACKAGES=("kernel" "kernel-core" "kernel-modules" "kernel-modules-core")
KERNEL_VERSION="6.12.10"
KERNEL_SPEC_VERSION="0"

for pkg in "${KERNEL_PACKAGES[@]}" ; do
  rpm --erase $pkg --nodeps || echo "expected failure"
done

# Had this as a reference:
# https://cbs.centos.org/kojifiles/packages/kernel/6.12.10/0.hs1.hsk.el10/x86_64/kernel-6.12.10-0.hs1.hsk.el10.x86_64.rpm
for pkg in "${KERNEL_PACKAGES[@]}" ; do
  rpm -ivh --nodeps "https://cbs.centos.org/kojifiles/packages/kernel/$KERNEL_VERSION/0.hs1.hsk.el10/$(arch)/${pkg}-${KERNEL_VERSION}-${KERNEL_SPEC_VERSION}.hs1.hsk.el${MAJOR_VERSION_NUMBER}.$(arch).rpm"
done
