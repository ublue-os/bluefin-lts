#!/usr/bin/env bash

set -xeuo pipefail

code --install-extension NVIDIA.nsight-vscode-edition
# cpptools is required by nsight-vscode
code --install-extension ms-vscode.cpptools
