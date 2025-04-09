#!/bin/bash

set -xeuo pipefail

dnf -y remove \
	setroubleshoot

dnf -y install \
	-x gnome-extensions-app \
	system-reinstall-bootc \
	gnome-disk-utility \
	distrobox \
	fastfetch \
	fpaste \
	gnome-shell-extension-{appindicator,dash-to-dock,blur-my-shell,caffeine} \
	just \
	powertop \
	tuned-ppd \
	fzf \
	glow \
	wl-clipboard \
	gum \
	jetbrains-mono-fonts-all \
	buildah

# Everything that depends on external repositories should be after this.
# Make sure to set them as disabled and enable them only when you are going to use their packages.
# We do, however, leave crb and EPEL enabled by default.

dnf config-manager --add-repo "https://pkgs.tailscale.com/stable/centos/${MAJOR_VERSION_NUMBER}/tailscale.repo"
dnf config-manager --set-disabled "tailscale-stable"
# FIXME: tailscale EPEL10 request: https://bugzilla.redhat.com/show_bug.cgi?id=2349099
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
	ublue-{motd,fastfetch,bling,rebase-helper,setup-services,polkit-rules} \
	uupd \
	bluefin-*

# Upstream ublue-os-signing bug, we are using /usr/etc for the container signing and bootc gets mad at this
# FIXME: remove this once https://github.com/ublue-os/packages/issues/245 is closed
cp -avf /usr/etc/. /etc
rm -rvf /usr/etc

dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:packages swap \
	centos-logos bluefin-logos

dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/ublue-os/staging/repo/epel-${MAJOR_VERSION_NUMBER}/ublue-os-staging-epel-$MAJOR_VERSION_NUMBER.repo"
dnf config-manager --set-disabled "copr:copr.fedorainfracloud.org:ublue-os:staging"
# FIXME: gsconnect EPEL10 request: https://bugzilla.redhat.com/show_bug.cgi?id=2349097
dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:staging install \
	gnome-shell-extension-{search-light,logo-menu,gsconnect}

dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/che/nerd-fonts/repo/centos-stream-${MAJOR_VERSION_NUMBER}/che-nerd-fonts-centos-stream-${MAJOR_VERSION_NUMBER}.repo"
dnf config-manager --set-disabled copr:copr.fedorainfracloud.org:che:nerd-fonts
dnf -y --enablerepo "copr:copr.fedorainfracloud.org:che:nerd-fonts" install \
	nerd-fonts
