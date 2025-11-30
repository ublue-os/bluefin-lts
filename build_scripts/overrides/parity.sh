#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail


# Mutter experimental features
echo "Configuring Mutter experimental features..."
MUTTER_EXP_FEATS="'scale-monitor-framebuffer', 'xwayland-native-scaling'"
# Check if image name contains gdx (simple check)
if [[ "${IMAGE_NAME:-}" =~ gdx ]]; then
    MUTTER_EXP_FEATS="'kms-modifiers', ${MUTTER_EXP_FEATS}"
fi

cat <<EOF > /usr/share/glib-2.0/schemas/zz1-bluefin-modifications-mutter-exp-feats.gschema.override
[org.gnome.mutter]
experimental-features=[${MUTTER_EXP_FEATS}]
EOF

# Schema compilation
echo "Compiling schemas..."
rm -f /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas &>/dev/null


echo "::endgroup::"
