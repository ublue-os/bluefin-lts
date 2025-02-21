#!/usr/bin/env bash

set -euox pipefail

# FIXME: add renovate rules for this (somehow?)
NVIDIA_DISTRO="rhel9"

dnf config-manager --add-repo "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_DISTRO}/$(arch)/cuda-${NVIDIA_DISTRO}.repo"
dnf clean expire-cache

dnf -y install --nogpgcheck \
  nvidia-container-toolkit \
  libnvidia-container1

systemctl enable ublue-nvctk-cdi.service
