#!/bin/bash

set -xeuo pipefail

# Enable sleep then hibernation by DEFAULT!
sed -i 's/#HandleLidSwitch=.*/HandleLidSwitch=suspend-then-hibernate/g' /usr/lib/systemd/logind.conf
sed -i 's/#HandleLidSwitchDocked=.*/HandleLidSwitchDocked=suspend-then-hibernate/g' /usr/lib/systemd/logind.conf
sed -i 's/#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend-then-hibernate/g' /usr/lib/systemd/logind.conf
sed -i 's/#SleepOperation=.*/SleepOperation=suspend-then-hibernate/g' /usr/lib/systemd/logind.conf
systemctl enable gdm.service
systemctl enable fwupd.service
systemctl enable rpm-ostree-countme.service
systemctl --global enable podman-auto-update.timer
systemctl enable rpm-ostree-countme.service
systemctl disable rpm-ostree.service
systemctl enable dconf-update.service
systemctl disable mcelog.service
systemctl enable tailscaled.service
systemctl enable uupd.timer
systemctl enable ublue-system-setup.service
systemctl --global enable ublue-user-setup.service
systemctl mask bootc-fetch-apply-updates.timer bootc-fetch-apply-updates.service
systemctl enable check-sb-key.service

# FIXME: upstream issue needs this: https://github.com/systemd/systemd/issues/35731
sed -i -e "s@PrivateTmp=.*@PrivateTmp=no@g" /usr/lib/systemd/system/systemd-resolved.service
# Resolved by default as DNS resolver
ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# FIXME: this does not yet work, the resolution service fails for somer reason
# enable systemd-resolved for proper name resolution
systemctl enable systemd-resolved.service
