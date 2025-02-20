#!/usr/bin/env bash

set -xeuo pipefail

FLAVOR="hwe"
export FLAVOR
"${SCRIPTS_PATH}/image-info-set"
