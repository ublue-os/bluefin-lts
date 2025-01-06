#!/bin/bash

# VSCode: Adding the repo and enabling some important extensions
dnf config-manager --add-repo "https://packages.microsoft.com/yumrepos/vscode"
dnf config-manager --set-disabled packages.microsoft.com_yumrepos_vscode
# TODO: Add the key from https://packages.microsoft.com/keys/microsoft.asc convert to gpg and add to /etc/pki/rpm-gpg
dnf -y --enablerepo packages.microsoft.com_yumrepos_vscode --nogpgcheck install code


# TODO: Bluefin does this via /usr/libexec script
# code --no-sandbox --install-extension ms-vscode-remote.remote-containers
# code --no-sandbox --install-extension ms-vscode-remote.remote-ssh
# code --no-sandbox --install-extension ms-azuretools.vscode-docker