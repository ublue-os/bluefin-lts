#!/usr/bin/env bash

set -euo pipefail

curl -fsSL https://pixi.sh/install.sh | sh
install -Dm0755 -t /usr/bin /root/.pixi/bin/pixi
