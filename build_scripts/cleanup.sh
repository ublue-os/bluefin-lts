#!/usr/bin/env bash

set -euo pipefail

# Image cleanup
# Specifically called by build.sh

# Hide Desktop Files. Hidden removes mime associations
sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' /usr/share/applications/fish.desktop

# Image-layer cleanup
shopt -s extglob

# shellcheck disable=SC2115
rm -rf /var/!(cache)
rm -rf /var/cache/!(rpm-ostree)
rm -rf /var/tmp
dnf clean all

ostree container commit # FIXME: Maybe will not be necessary in the future. Reassess in a few years.
bootc container lint
