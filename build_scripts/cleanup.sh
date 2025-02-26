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
