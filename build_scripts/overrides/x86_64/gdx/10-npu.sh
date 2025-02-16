!/usr/bin/env bash

set -euox pipefail

dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/xanderlent/intel-npu-driver/repo/centos-stream-10/xanderlent-intel-npu-driver-centos-stream-10.repo"
dnf config-manager --set-disabled "copr:copr.fedorainfracloud.org:xanderlent:intel-npu-driver"
dnf -y --enablerepo "copr:copr.fedorainfracloud.org:xanderlent:intel-npu-driver" install \
	intel-npu-level-zero
