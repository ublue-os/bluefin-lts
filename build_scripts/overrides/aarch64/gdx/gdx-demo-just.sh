#!/usr/bin/env bash

set -xeuo pipefail

#Add the GDX demo to the Just menu
cat /run/context/system_files_overrides/aarch64-gdx/usr/share/ublue-os/just/66-ampere.just >> /usr/share/ublue-os/just/60-custom.just
