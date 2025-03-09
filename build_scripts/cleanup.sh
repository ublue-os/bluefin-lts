#!/usr/bin/env bash

set -xeuo pipefail

# Image cleanup
# Specifically called by build.sh

# Hide Desktop Files. Hidden removes mime associations
sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/fish.desktop

# The compose repos we used during the build are point in time repos that are
# not updated, so we don't want to leave them enabled.
dnf config-manager --set-disabled baseos-compose,appstream-compose

# Image-layer cleanup
shopt -s extglob

dnf clean all
rm -rf /.gitkeep \
  /var/tmp \
  /var/lib/{dnf,rhsm} \
  /var/cache/* \
  /boot

mkdir -p /boot /var/tmp

# Remove non-empty log files so that we dont get bootc lint errors
find /var/log -type f -exec 'bash' '-c' "[ -s {} ] && rm {}" ';'

# Set file to globally readable
# FIXME: This should not be necessary, needs to be cleaned up somewhere else
chmod 644 "/usr/share/ublue-os/image-info.json"

# FIXME: use --fix option once https://github.com/containers/bootc/pull/1152 is merged
bootc container lint --fatal-warnings
