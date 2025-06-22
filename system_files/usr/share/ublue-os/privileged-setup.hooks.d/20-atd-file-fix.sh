#!/usr/bin/bash

source /usr/lib/ublue/setup-services/libsetup.sh

version-script tailscale-lts privileged 1 || exit 0

set -xeuo pipefail

# Create the folder for at jobs
sudo mkdir -p /var/spool/at