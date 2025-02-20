#!/usr/bin/env bash

set -xeuo pipefail

FLAVOR="dx"
export FLAVOR
"${SCRIPTS_PATH}/image-info-set"
