#!/usr/bin/env bash

set -xeuo pipefail

# Bucket list again, this needs to be fixed upstream!

TARGET_FLATPAK_FILE="/etc/ublue-os/system-flatpaks.list"

sed -i "/org\.mozilla.*/d" "$TARGET_FLATPAK_FILE"
echo "org.chromium.Chromium" >> "$TARGET_FLATPAK_FILE"

sed -i "s/org.mozilla.Firefox/org.chromium.Chromium/g" /usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override
