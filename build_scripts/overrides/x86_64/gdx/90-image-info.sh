#!/usr/bin/env bash

set -xeuo pipefail

FLAVOR="gdx"
IMAGE_NAME="bluefin-${FLAVOR}"
IMAGE_REF="ostree-image-signed:docker://ghcr.io/ublue-os/bluefin-${FLAVOR}"
"${SCRIPTS_PATH}/image-info-set"
