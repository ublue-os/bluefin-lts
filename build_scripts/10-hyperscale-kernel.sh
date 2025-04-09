#!/usr/bin/env bash

set -xeuo pipefail

# The hyperscale SIG's kernel straight from their official builds

dnf -y install centos-release-hyperscale-kernel
dnf config-manager --set-disabled "centos-hyperscale,centos-hyperscale-kernel"
dnf --enablerepo="centos-hyperscale" --enablerepo="centos-hyperscale-kernel" -y update kernel
