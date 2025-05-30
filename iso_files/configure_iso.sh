#!/usr/bin/env bash

set -x

# dnf install -y centos-release-hyperscale
dnf config-manager --set-enabled crb

dnf install -y \
  anaconda \
  anaconda-install-env-deps \
  anaconda-live

systemctl disable brew-setup.service
systemctl disable uupd.timer
systemctl --global disable podman-auto-update.timer
systemctl disable rpm-ostree.service
systemctl disable uupd.timer
systemctl disable ublue-system-setup.service
systemctl --global disable ublue-user-setup.service
systemctl disable check-sb-key.service
