#!/usr/bin/env bash

set -xeuo pipefail

# Migrate regular non-DX HWE users from the legacy ublue-os registry.
# DX-HWE and GDX use their own migration paths and are excluded by build.sh.
systemctl enable bluefin-lts-migration.timer
