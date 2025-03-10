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

STABLE_KUBE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
STABLE_KUBE_VERSION_MAJOR="${STABLE_KUBE_VERSION%.*}"
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${STABLE_KUBE_VERSION_MAJOR}/rpm/
enabled=0
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${STABLE_KUBE_VERSION_MAJOR}/rpm/repodata/repomd.xml.key
EOF

dnf install -y --enablerepo="kubernetes" \
	kubectl \
	kubeadm

GITHUB_LIKE_ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')"
KIND_LATEST_VERSION="$(curl -L https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r ".tag_name")"

KIND_TMP="$(mktemp -d)"

clean_kind() {
  rm -rf "${KIND_TMP}"
}
trap clean_kind EXIT

SHA_TYPE="256"
KIND_BIN_NAME="kind-linux-${GITHUB_LIKE_ARCH}"
curl --retry 3 -Lo "${KIND_TMP}/${KIND_BIN_NAME}" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_LATEST_VERSION}/kind-linux-${GITHUB_LIKE_ARCH}"
curl --retry 3 -Lo "${KIND_TMP}/${KIND_BIN_NAME}.sha${SHA_TYPE}sum" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_LATEST_VERSION}/kind-linux-${GITHUB_LIKE_ARCH}.sha${SHA_TYPE}sum"
pushd "${KIND_TMP}"
"sha${SHA_TYPE}sum" --strict -c "${KIND_TMP}/${KIND_BIN_NAME}.sha${SHA_TYPE}sum"
popd

install -Dpm0755 "${KIND_TMP}/${KIND_BIN_NAME}" "/usr/bin/kind"
