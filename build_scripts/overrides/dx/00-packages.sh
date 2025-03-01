#!/bin/bash

set -xeuo pipefail

# FIXME: just install uv regularly, this should be out of epel testing after 10-02-25 or so
# dnf --enablerepo="epel-testing" install -y uv

dnf install -y \
	python3-ramalama

# VSCode on the base image!
dnf config-manager --add-repo "https://packages.microsoft.com/yumrepos/vscode"
dnf config-manager --set-disabled packages.microsoft.com_yumrepos_vscode
update-crypto-policies --set LEGACY
rpm --import https://packages.microsoft.com/keys/microsoft.asc
dnf -y --enablerepo packages.microsoft.com_yumrepos_vscode install code
update-crypto-policies --set DEFAULT

dnf config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo"
dnf config-manager --set-disabled docker-ce-stable
dnf -y --enablerepo docker-ce-stable install \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-buildx-plugin \
	docker-compose-plugin
