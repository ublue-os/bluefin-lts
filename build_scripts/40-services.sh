#!/bin/bash

set -xeuo pipefail

sed -i 's|uupd|& --disable-module-distrobox|' /usr/lib/systemd/system/uupd.service

# Enable sleep then hibernation by DEFAULT!
sed -i 's/#HandleLidSwitch=.*/HandleLidSwitch=suspend-then-hibernate/g' /usr/lib/systemd/logind.conf
sed -i 's/#HandleLidSwitchDocked=.*/HandleLidSwitchDocked=suspend-then-hibernate/g' /usr/lib/systemd/logind.conf
sed -i 's/#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend-then-hibernate/g' /usr/lib/systemd/logind.conf
sed -i 's/#SleepOperation=.*/SleepOperation=suspend-then-hibernate/g' /usr/lib/systemd/logind.conf
systemctl enable brew-setup.service
systemctl enable gdm.service
systemctl enable firewalld.service
systemctl enable fwupd.service
systemctl --global enable podman-auto-update.timer
systemctl disable rpm-ostree.service
systemctl enable dconf-update.service
# systemctl --global enable bazaar.service
systemctl disable mcelog.service
systemctl enable tailscaled.service
systemctl enable uupd.timer
systemctl enable ublue-system-setup.service
systemctl --global enable ublue-user-setup.service
# Installs the OS-managed Homebrew packages (ChairLift) at login. A user
# preset is not applied to existing users, so enable it globally.
systemctl --global enable brew-preinstall.service
# The ChairLift icons come from system_files; refresh the hicolor cache so
# users without the cask's ~/.local copy (everyone but UID 1000) see them.
gtk-update-icon-cache -f -t /usr/share/icons/hicolor
# ChairLift: fail the build if the image half of the ublue-os/tap chairlift
# cask is missing
for i in bin/chairlift-helper bin/brew-preinstall libexec/brew-preinstall libexec/bootc-update-stage; do
    test -x "/usr/$i"
done
for i in livery updates firstrun printers; do
    test -f "/usr/share/glib-2.0/schemas/io.projectbluefin.chairlift.${i}.gschema.xml"
done
test -f /usr/share/polkit-1/actions/io.projectbluefin.chairlift.ublue.policy
test -f /usr/share/polkit-1/actions/io.projectbluefin.chairlift.bootc.policy
grep -qx 'cask "ublue-os/tap/chairlift"' /usr/share/ublue-os/homebrew/preinstall.d/chairlift.Brewfile
test -f /usr/share/chairlift/config.yml
test -f /usr/share/chairlift/channels.yml
test "$(systemctl --global is-enabled brew-preinstall.service)" = enabled
grep -aq io.projectbluefin.chairlift /usr/share/icons/hicolor/icon-theme.cache
systemctl mask bootc-fetch-apply-updates.timer bootc-fetch-apply-updates.service
systemctl disable sshd.service

# Disable lastlog display on previous failed login in GDM (This makes logins slow)
authselect enable-feature with-silent-lastlog

# Enable polkit rules for fingerprint sensors via fprintd
authselect enable-feature with-fingerprint

sed -i -e "s@PrivateTmp=.*@PrivateTmp=no@g" /usr/lib/systemd/system/systemd-resolved.service
# FIXME: this does not yet work, the resolution service fails for somer reason
# enable systemd-resolved for proper name resolution
systemctl enable systemd-resolved.service
