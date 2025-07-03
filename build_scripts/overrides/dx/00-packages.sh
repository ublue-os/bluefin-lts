#!/bin/bash

set -xeuo pipefail

dnf install -y \
	python3-ramalama

# VSCode on the base image!
dnf config-manager --add-repo "https://packages.microsoft.com/yumrepos/vscode"
dnf config-manager --set-disabled packages.microsoft.com_yumrepos_vscode
dnf -y --enablerepo packages.microsoft.com_yumrepos_vscode --nogpgcheck  install code

dnf config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo"
dnf config-manager --set-disabled docker-ce-stable
dnf -y --enablerepo docker-ce-stable install \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-buildx-plugin \
	docker-compose-plugin

dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:packages install \
  libvirt \
  libvirt-daemon-kvm \
  libvirt-nss \
  virt-install \
  ublue-os-libvirt-workarounds

STABLE_KUBE_VERSION="$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r .tag_name)"
STABLE_KUBE_VERSION_MAJOR="${STABLE_KUBE_VERSION%.*}"
GITHUB_LIKE_ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')"
KIND_LATEST_VERSION="$(curl -L https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r ".tag_name")"
KZERO_LATEST_VERSION="$(curl -L https://api.github.com/repos/k0sproject/k0s/releases/latest | jq -r ".tag_name")"
KZEROCTL_LATEST_VERSION="$(curl -L https://api.github.com/repos/k0sproject/k0sctl/releases/latest | jq -r ".tag_name")"
KUBE_TMP="$(mktemp -d)"

trap "rm -rf ${KUBE_TMP}" EXIT

KIND_BIN_NAME="kind-linux-${GITHUB_LIKE_ARCH}"
DEFAULT_RETRY=3
pushd "${KUBE_TMP}"
curl --retry "${DEFAULT_RETRY}" -Lo "${KIND_BIN_NAME}" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_LATEST_VERSION}/${KIND_BIN_NAME}"
curl --retry "${DEFAULT_RETRY}" -Lo "${KIND_BIN_NAME}.sha256sum" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_LATEST_VERSION}/${KIND_BIN_NAME}.sha256sum"
curl --retry "${DEFAULT_RETRY}" -LO "https://dl.k8s.io/release/${STABLE_KUBE_VERSION}/bin/linux/${GITHUB_LIKE_ARCH}/kubectl"
curl --retry "${DEFAULT_RETRY}" -LO "https://dl.k8s.io/release/${STABLE_KUBE_VERSION}/bin/linux/${GITHUB_LIKE_ARCH}/kubectl.sha256"
curl --retry "${DEFAULT_RETRY}" -LO "https://github.com/k0sproject/k0sctl/releases/download/${KZEROCTL_LATEST_VERSION}/k0sctl-linux-${GITHUB_LIKE_ARCH}"
curl --retry "${DEFAULT_RETRY}" -Lo "kzeroctl-checksums.txt" "https://github.com/k0sproject/k0sctl/releases/download/${KZEROCTL_LATEST_VERSION}/checksums.txt"
curl --retry "${DEFAULT_RETRY}" -LO "https://github.com/k0sproject/k0s/releases/download/${KZERO_LATEST_VERSION}/k0s-${KZERO_LATEST_VERSION}-${GITHUB_LIKE_ARCH}"
curl --retry "${DEFAULT_RETRY}" -Lo "kzero-checksums.txt" "https://github.com/k0sproject/k0s/releases/download/${KZERO_LATEST_VERSION}/sha256sums.txt"

grep "k0s-${KZERO_LATEST_VERSION}-${GITHUB_LIKE_ARCH}" kzero-checksums.txt | grep -v "sig\|exe" | sha256sum --strict --check
grep "k0sctl-linux-${GITHUB_LIKE_ARCH}" kzeroctl-checksums.txt | sha256sum --strict --check
sha256sum --strict --check "${KUBE_TMP}/${KIND_BIN_NAME}.sha256sum"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --strict --check

install -Dpm0755 "${KIND_BIN_NAME}" "/usr/bin/kind"
install -Dpm0755 "./kubectl" "/usr/bin/kubectl"
install -Dpm0755 "./k0sctl-linux-${GITHUB_LIKE_ARCH}" "/usr/bin/k0sctl"
install -Dpm0755 "./k0s-${KZERO_LATEST_VERSION}-${GITHUB_LIKE_ARCH}" "/usr/bin/k0s"
popd

