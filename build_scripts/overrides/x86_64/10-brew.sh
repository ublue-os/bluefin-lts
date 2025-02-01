#!/bin/bash

set -xeuo pipefail

mkdir -p /var/home

dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:staging install ublue-brew

touch /.dockerenv
curl --retry 3 -Lo /tmp/brew-install https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
chmod +x /tmp/brew-install
/tmp/brew-install
tar --zstd -cvf /usr/share/homebrew.tar.zst /home/linuxbrew
rm -f /.dockerenv
# Clean up brew artifacts on the image.
rm -rf /home/linuxbrew /root/.cache
rm -r /var/home
