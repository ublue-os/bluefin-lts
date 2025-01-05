# VSCode: Adding the repo and enabling some important extensions
dnf config-manager --add-repo "https://packages.microsoft.com/yumrepos/vscode"
dnf config-manager --set-disabled packages.microsoft.com_yumrepos_vscode
# TODO: Add the key
dnf -y --enablerepo packages.microsoft.com_yumrepos_vscode --nogpgcheck install code

code --no-sandbox --install-extension ms-vscode-remote.remote-containers
code --no-sandbox --install-extension ms-vscode-remote.remote-ssh
code --no-sandbox --install-extension ms-azuretools.vscode-docker