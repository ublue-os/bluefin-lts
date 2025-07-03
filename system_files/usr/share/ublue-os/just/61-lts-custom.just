install-system-flatpaks:
    #!/usr/bin/env bash
    flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
    xargs flatpak --system -y install --or-update < /etc/ublue-os/system-flatpaks.list

bluefin-cli:
    /usr/libexec/ublue-bling

alias switch-stream := rebase-helper
alias switch-streams := rebase-helper
alias rollback-helper := rebase-helper
alias devmode := toggle-devmode

rebase-helper:
    /usr/libexec/ublue-rebase-helper

toggle-devmode:
    /usr/libexec/ublue-dx-helper

tailscale-exitnode:
    /usr/libexec/ublue-ts-exit-node
