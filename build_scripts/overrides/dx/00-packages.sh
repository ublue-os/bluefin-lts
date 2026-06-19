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

dnf -y install \
  libvirt \
  libvirt-daemon-kvm \
  libvirt-nss \
  virt-install \
  https://download.copr.fedorainfracloud.org/results/ublue-os/packages/fedora-44-x86_64/10417407-ublue-os-libvirt-workarounds/ublue-os-libvirt-workarounds-1.1-1.fc44.noarch.rpm

dnf -y --setopt=install_weak_deps=False install \
  cockpit-bridge \
  cockpit-machines \
  cockpit-networkmanager \
  cockpit-ostree \
  cockpit-podman \
  cockpit-selinux \
  cockpit-storaged \
  cockpit-system
