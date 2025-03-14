#!/usr/bin/bash

source /usr/lib/ublue/setup-services/libsetup.sh

version-script vscode-lts user 1 || exit 1

set -x

#!/usr/bin/bash

source /usr/lib/ublue/setup-services/libsetup.sh

ARCH=$(arch)
if [ "$ARCH" != "aarch64"] ; then
    echo "export PATH=\$PATH:/root/.pixi/bin" >> "$HOME"/.bashrc
    echo "export PATH=\$PATH:/root/.pixi/bin" >> "$HOME"/.zshrc
    echo "export PATH=\$PATH:/root/.pixi/bin" >> "$HOME"/.config/fish/config.fish
fi
