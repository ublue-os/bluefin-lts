#!/usr/bin/bash

source /usr/lib/ublue/setup-services/libsetup.sh

version-script flatpaks-lts privileged 1 || exit 0

set -x

# Set up Firefox default configuration
ARCH=$(arch)
if [ "$ARCH" != "aarch64"] ; then
	mkdir -p "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/${ARCH}/stable/defaults/pref"
	rm -f "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/${ARCH}/stable/defaults/pref/*bluefin*.js"
	/usr/bin/cp -rf /usr/share/ublue-os/firefox-config/* "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/${ARCH}/stable/defaults/pref/"
fi

notify-send "Welcome to Bluefin LTS" "Your computer is ready!" --app-name="Flatpak Manager Service" -u NORMAL
