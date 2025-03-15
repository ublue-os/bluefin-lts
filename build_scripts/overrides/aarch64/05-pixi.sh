#!/usr/bin/env bash

set -xeuo pipefail


clean_kind() {
  rm -rf "${KIND_TMP}"
}
trap clean_kind EXIT

PIXI_TMP="$(mktemp -d)"
PIXI_FILENAME="pixi-$(arch)-unknown-linux-musl.tar.gz"
SHA_TYPE="256"

pushd "${PIXI_TMP}"
wget "https://github.com/prefix-dev/pixi/releases/latest/download/${PIXI_FILENAME}" 
wget "https://github.com/prefix-dev/pixi/releases/latest/download/${PIXI_FILENAME}.sha${SHA_TYPE}" 
"sha${SHA_TYPE}sum" --strict -c "${PIXI_FILENAME}.sha${SHA_TYPE}"
tar xf "${PIXI_FILENAME}"
popd

install -Dpm0755 "${PIXI_TMP}/pixi" "/usr/bin/pixi"
