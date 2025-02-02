#!/usr/bin/env bash

set -xeuo pipefail

# FIXME: make this part prettier, i dont know how to do it right now
cat >/etc/dconf/db/distro.d/05-dx-logomenu-extension <<EOF
[org/gnome/shell/extensions/Logo-menu]
show-boxbuddy=true
EOF

cat >/usr/share/glib-2.0/schemas/zz1-dx-modifications.gschema.override <<EOF
[org/gnome/shell/extensions/Logo-menu]
show-boxbuddy=true
EOF
