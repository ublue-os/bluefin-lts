#!/usr/bin/env bash

set -xeuo pipefail

tee -a /etc/ublue-os/system-flatpaks.list <<EOF
io.podman_desktop.PodmanDesktop
io.github.getnf.embellish
io.github.dvlv.boxbuddyrs
EOF
