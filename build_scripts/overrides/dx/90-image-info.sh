#!/usr/bin/env bash

set -xeuo pipefail

FLAVOR="dx"

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_NAME="$(jq -c -r '."image-name"' "${IMAGE_INFO}")"
IMAGE_REF="$(jq -c -r '."image-ref"' "${IMAGE_INFO}")"

jq -f /dev/stdin "${IMAGE_INFO}" <<EOF
."image-name" = "${IMAGE_NAME}-${FLAVOR}" | \
."image-flavor" = "${FLAVOR}" | \
."image-ref" = "${IMAGE_REF}-${FLAVOR}"
EOF
