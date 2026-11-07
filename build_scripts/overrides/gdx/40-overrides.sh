#!/usr/bin/env bash

set -xeuo pipefail

sed -i "/experimental-features/ s/\]/, 'kms-modifiers'&/" /usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override
echo "Compiling gschema to include bluefin setting overrides"
glib-compile-schemas /usr/share/glib-2.0/schemas

# Canary migration: GDX users only — enable the migration timer that switches
# legacy ublue-os/bluefin-gdx:lts → projectbluefin/bluefin-lts-nvidia:stable
systemctl enable bluefin-lts-migration.timer
