#!/bin/bash

set -xeuo pipefail

# VSCode on the base image!
dnf config-manager --add-repo "https://packages.microsoft.com/yumrepos/vscode"
dnf config-manager --set-disabled packages.microsoft.com_yumrepos_vscode
dnf -y --enablerepo packages.microsoft.com_yumrepos_vscode --nogpgcheck  install code

dnf config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo"
dnf config-manager --set-disabled docker-ce-stable
dnf -y --enablerepo docker-ce-stable install \
	docker-ce \
	docker-ce-cli \
    docker-model-plugin \
	containerd.io \
	docker-buildx-plugin \
	docker-compose-plugin

dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:packages install \
  libvirt \
  libvirt-daemon-kvm \
  libvirt-nss \
  virt-install \
  ublue-os-libvirt-workarounds
