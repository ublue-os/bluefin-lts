#!/usr/bin/env bash

set -xeuo pipefail

source /usr/lib/ublue/setup-services/libsetup.sh

version-script gdx-vscode-lts user 1 || exit 0

code --install-extension NVIDIA.nsight-vscode-edition
# cpptools is required by nsight-vscode
code --install-extension ms-vscode.cpptools
