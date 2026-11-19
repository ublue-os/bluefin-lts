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
systemctl --global enable ublue-gtk3-theme-sync.service
# ChairLift: build.sh copies it on non-DX images only (not dx, not gdx).
# Fail the build if a non-DX image misses any of the image half of the
# projectbluefin/tap chairlift cask, or a DX image has any of it.
CHAIRLIFT_FILES=(
    /usr/bin/chairlift-helper
    /usr/bin/brew-preinstall
    /usr/libexec/brew-preinstall
    /usr/libexec/bootc-update-stage
    /usr/lib/systemd/user/brew-preinstall.service
    /usr/share/glib-2.0/schemas/io.projectbluefin.chairlift.livery.gschema.xml
    /usr/share/glib-2.0/schemas/io.projectbluefin.chairlift.updates.gschema.xml
    /usr/share/glib-2.0/schemas/io.projectbluefin.chairlift.firstrun.gschema.xml
    /usr/share/glib-2.0/schemas/io.projectbluefin.chairlift.printers.gschema.xml
    /usr/share/polkit-1/actions/io.projectbluefin.chairlift.ublue.policy
    /usr/share/polkit-1/actions/io.projectbluefin.chairlift.bootc.policy
    /usr/share/applications/io.projectbluefin.chairlift.desktop
    /usr/share/ublue-os/homebrew/preinstall.d/chairlift.Brewfile
    /usr/share/chairlift/config.yml
    /usr/share/chairlift/channels.yml
)
if [ "${ENABLE_DX:-0}" != "1" ] && [ "${ENABLE_GDX:-0}" != "1" ]; then
    # Installs the OS-managed Homebrew packages (ChairLift) at login. A user
    # preset is not applied to existing users, so enable it globally.
    systemctl --global enable brew-preinstall.service
    # Compass is installed by brew-preinstall on non-DX images. A user preset
    # is not applied to existing users, so enable its unit globally too.
    systemctl --global enable compass.service
    test -f /usr/share/ublue-os/homebrew/preinstall.d/compass.Brewfile
    test -f /usr/lib/systemd/user/compass.service
    test "$(systemctl --global is-enabled compass.service)" = enabled
    # The ChairLift icons come from the image; refresh the hicolor cache so
    # users without the cask's ~/.local copy (everyone but UID 1000) see them.
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor
    for i in "${CHAIRLIFT_FILES[@]}"; do
        test -f "$i"
    done
    test -x /usr/bin/chairlift-helper
    test -x /usr/libexec/brew-preinstall
    grep -qx 'cask "projectbluefin/tap/chairlift"' /usr/share/ublue-os/homebrew/preinstall.d/chairlift.Brewfile
    test "$(systemctl --global is-enabled brew-preinstall.service)" = enabled
    grep -aq io.projectbluefin.chairlift /usr/share/icons/hicolor/icon-theme.cache
else
    for i in "${CHAIRLIFT_FILES[@]}"; do
        test ! -e "$i"
    done
    test ! -e /usr/share/ublue-os/homebrew/preinstall.d
    if systemctl --global is-enabled brew-preinstall.service; then
        echo "brew-preinstall.service is enabled on a DX image"
        exit 1
    fi
    if systemctl --global is-enabled compass.service; then
        echo "compass.service is enabled on a DX image"
        exit 1
    fi
fi
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
