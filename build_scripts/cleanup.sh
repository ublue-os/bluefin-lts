#!/usr/bin/env bash

set -euo pipefail

# Image cleanup
# Specifically called by build.sh

# Hide Desktop Files. Hidden removes mime associations
sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/fish.desktop

# Signing needs to be as late as possible so that it wont be overwritten by anything, ever.
dnf -y install /tmp/rpms/ublue-os-signing.noarch.rpm
# ublue-os-signing incorrectly puts files under /usr/etc and bootc container lint gets mad at this.
# FIXME: dear lord fix this upstream https://github.com/ublue-os/config/pull/311
cp -av /usr/etc /etc
rm -rvf /usr/etc

# Image-layer cleanup
shopt -s extglob

# shellcheck disable=SC2115
rm -rf /var/!(cache)
rm -rf /var/cache/!(rpm-ostree)
rm -rf /var/tmp
dnf clean all

ostree container commit # FIXME: Maybe will not be necessary in the future. Reassess in a few years.
bootc container lint
