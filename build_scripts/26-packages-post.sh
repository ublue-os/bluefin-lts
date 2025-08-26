#!/usr/bin/env bash

set -xeuo pipefail

# Fancy CentOS icon on the fastfetch
sed -i "s/󰣛//g" /usr/share/ublue-os/fastfetch.jsonc

# Fix 1969 date getting returned on Fastfetch (upstream issue)
# FIXME: check if this issue is fixed upstream at some point. (28-02-2025) https://github.com/ostreedev/ostree/issues/1469
sed -i -e "s@ls -alct /@&var/log@g" /usr/share/ublue-os/fastfetch.jsonc

# Automatic wallpaper changing by month
HARDCODED_RPM_MONTH="12"
sed -i "/picture-uri/ s/${HARDCODED_RPM_MONTH}/$(date +%m)/" "/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override"
glib-compile-schemas /usr/share/glib-2.0/schemas

# Required for bluefin faces to work without conflicting with a ton of packages
rm -f /usr/share/pixmaps/faces/* || echo "Expected directory deletion to fail"
mv /usr/share/pixmaps/faces/bluefin/* /usr/share/pixmaps/faces
rm -rf /usr/share/pixmaps/faces/bluefin

# This should only be enabled on `-dx`
sed -i "/^show-boxbuddy=.*/d" /etc/dconf/db/distro.d/04-bluefin-logomenu-extension
sed -i "/^show-boxbuddy=.*/d" /usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override
sed -i "/.*io.github.dvlv.boxbuddyrs.*/d" /etc/ublue-os/system-flatpaks.list

# Offline Bluefin documentation
curl --retry 3 -Lo /tmp/bluefin.pdf https://github.com/ublue-os/bluefin-docs/releases/download/0.1/bluefin.pdf
install -Dm0644 -t /usr/share/doc/bluefin/ /tmp/bluefin.pdf

# Add Flathub by default
mkdir -p /etc/flatpak/remotes.d
curl --retry 3 -o /etc/flatpak/remotes.d/flathub.flatpakrepo "https://dl.flathub.org/repo/flathub.flatpakrepo"

# move the custom just
mv /usr/share/ublue-os/just/61-lts-custom.just /usr/share/ublue-os/just/60-custom.just 

/usr/sbin/depmod -a `ls -1 /lib/modules/ | tail -1`


# Git clone bluefin and get the Bazaar config and copy it over
mkdir -p "/usr/share/ublue-os"
echo "Cloning the repository with depth 1..."
git clone --depth 1 "https://github.com/ublue-os/bluefin.git" "/tmp/bluefin_repo"
cp -avf "/tmp/bluefin_repo/system_files/shared/usr/share/ublue-os/bazaar" "/usr/share/ublue-os/"


# Generate initramfs image after installing Bluefin branding because of Plymouth subpackage
# Add resume module so that hibernation works
echo "add_dracutmodules+=\" resume \"" >/etc/dracut.conf.d/resume.conf
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//' | tail -n 1)"
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
