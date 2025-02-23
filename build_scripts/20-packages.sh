#!/bin/bash

set -xeuo pipefail

dnf -y remove \
	setroubleshoot

dnf -y install \
	-x gnome-extensions-app \
	gnome-disk-utility \
	distrobox \
	fastfetch \
	fpaste \
	gnome-shell-extension-{appindicator,dash-to-dock,blur-my-shell} \
	just \
	powertop \
	tuned-ppd \
	fzf \
	glow \
	wl-clipboard \
	gum \
	jetbrains-mono-fonts-all

# Everything that depends on external repositories should be after this.
# Make sure to set them as disabled and enable them only when you are going to use their packages.
# We do, however, leave crb and EPEL enabled by default.

dnf config-manager --add-repo "https://pkgs.tailscale.com/stable/centos/${MAJOR_VERSION_NUMBER}/tailscale.repo"
dnf config-manager --set-disabled "tailscale-stable"
dnf -y --enablerepo "tailscale-stable" install \
	tailscale

dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/ublue-os/packages/repo/epel-$MAJOR_VERSION_NUMBER/ublue-os-packages-epel-$MAJOR_VERSION_NUMBER.repo"
dnf config-manager --set-disabled "copr:copr.fedorainfracloud.org:ublue-os:packages"
dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:packages install \
	-x bluefin-logos \
	ublue-os-just \
	ublue-os-luks \
	ublue-os-signing \
	ublue-os-udev-rules \
	ublue-os-update-services \
	ublue-{motd,fastfetch,bling,rebase-helper,setup-services} \
	uupd \
	bluefin-*

# Upstream ublue-os-signing bug, we are using /usr/etc for the container signing and bootc gets mad at this
cp -avf /usr/etc/. /etc
rm -rvf /usr/etc

dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:packages swap \
	centos-logos bluefin-logos

dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/ublue-os/staging/repo/epel-$MAJOR_VERSION_NUMBER/ublue-os-staging-epel-$MAJOR_VERSION_NUMBER.repo"
dnf config-manager --set-disabled "copr:copr.fedorainfracloud.org:ublue-os:staging"
dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:staging install \
	jetbrains-mono-fonts-all \
	gnome-shell-extension-{search-light,gsconnect,logo-menu,caffeine}

dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/che/nerd-fonts/repo/centos-stream-${MAJOR_VERSION_NUMBER}/che-nerd-fonts-centos-stream-${MAJOR_VERSION_NUMBER}.repo"
dnf config-manager --set-disabled copr:copr.fedorainfracloud.org:che:nerd-fonts
dnf -y --enablerepo "copr:copr.fedorainfracloud.org:che:nerd-fonts" install \
	nerd-fonts

# This is required so homebrew works indefinitely.
# Symlinking it makes it so whenever another GCC version gets released it will break if the user has updated it without-
# the homebrew package getting updated through our builds.
# We could get some kind of static binary for GCC but this is the cleanest and most tested alternative. This Sucks.
dnf -y --setopt=install_weak_deps=False install gcc
