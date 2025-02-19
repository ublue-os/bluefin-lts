#!/usr/bin/env bash

set -xeuo pipefail

FLAVOR="gdx"

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_NAME="$(jq -c -r '."image-name"' "${IMAGE_INFO}")"
IMAGE_REF="ostree-image-signed:docker://ghcr.io/ublue-os/bluefin-gdx"


jq -f /dev/stdin "${IMAGE_INFO}" <<EOF
."image-name" = "bluefin-${FLAVOR}" | \
."image-flavor" = "${FLAVOR}" | \
."image-ref" = "${IMAGE_REF}"
EOF
