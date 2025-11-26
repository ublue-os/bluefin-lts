#!/usr/bin/env bash

set -xeuo pipefail

# Image cleanup
# Specifically called by build.sh

# The compose repos we used during the build are point in time repos that are
# not updated, so we don't want to leave them enabled.
dnf config-manager --set-disabled baseos-compose,appstream-compose

dnf clean all

# https://github.com/ublue-os/bluefin-lts/issues/841
# WORKAROUND PENDING ACTUAL FIX https://issues.redhat.com/browse/RHEL-113906
# Create and install SELinux policy module for tuned-ppd filesystem access
cat > /tmp/tuned_ppd_hotfix.te << 'EOF'
module tuned_ppd_hotfix 1.0;

require {
    type tuned_ppd_t;
    type fs_t;
    type xfs_t;
    type ext4_t;
    class filesystem getattr;
}

# Allow tuned-ppd to get filesystem attributes on xattr filesystems
allow tuned_ppd_t { fs_t xfs_t ext4_t }:filesystem getattr;
EOF

# Compile and install the module
checkmodule -M -m -o /tmp/tuned_ppd_hotfix.mod /tmp/tuned_ppd_hotfix.te
semodule_package -o /tmp/tuned_ppd_hotfix.pp -m /tmp/tuned_ppd_hotfix.mod
semodule -i /tmp/tuned_ppd_hotfix.pp

# Clean up temporary files
rm -f /tmp/tuned_ppd_hotfix.te /tmp/tuned_ppd_hotfix.mod /tmp/tuned_ppd_hotfix.pp


rm -rf /.gitkeep
find /var -mindepth 1 -delete
find /boot -mindepth 1 -delete
mkdir -p /var /boot

# Make /usr/local writeable
ln -s /var/usrlocal /usr/local

# We need this else anything accessing image-info fails
# FIXME: Figure out why this doesnt have the right permissions by default
chmod 644 /usr/share/ublue-os/image-info.json

# FIXME: use --fix option once https://github.com/containers/bootc/pull/1152 is merged
bootc container lint --fatal-warnings || true
