#!/bin/bash

set -xeuo pipefail

dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:packages install ublue-brew

# Forcefully enable brew setup since the preset doesnt seem to work?
systemctl enable brew-setup.service
