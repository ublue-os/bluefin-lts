#!/usr/bin/env bash

source /usr/lib/ublue/setup-services/libsetup.sh

version-script gdx-vscode-lts user 1 || exit 0

set -xeuo pipefail

# cpptools is required by nsight-vscode
code --install-extension ms-vscode.cpptools
code --install-extension NVIDIA.nsight-vscode-edition
