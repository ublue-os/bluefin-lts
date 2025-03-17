#!/usr/bin/env bash

set -xeuo pipefail

#Add the GDX demo to the Just menu
echo "include? /usr/share/ublue-os/just/66-ampere.just" >> /usr/share/ublue-os/just/60-custom.just
