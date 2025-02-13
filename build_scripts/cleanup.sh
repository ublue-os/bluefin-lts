#!/usr/bin/env bash

set -xeuo pipefail

# Image cleanup
# Specifically called by build.sh

# Hide Desktop Files. Hidden removes mime associations
sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/fish.desktop

# Signing needs to be as late as possible so that it wont be overwritten by anything, ever.
dnf -y install /tmp/rpms/ublue-os-signing.noarch.rpm
# ublue-os-signing incorrectly puts files under /usr/etc and bootc container lint gets mad at this.
# FIXME: dear lord fix this upstream https://github.com/ublue-os/config/pull/311
cp -avf /usr/etc/. /etc
rm -rvf /usr/etc

# Image-layer cleanup
shopt -s extglob

# shellcheck disable=SC2115
rm -rf /var/!(cache)
rm -rf /var/cache/!(rpm-ostree)
# Ensure /var/tmp exists, FIXME: remove this once this is fixed upstream
mkdir -p /var/tmp
# Remove gitkeep file if that still is on / for any reason
rm -f /.gitkeep
dnf clean all

# FIXME: bootc container lint --fix will replace this
ostree container commit
bootc container lint
