!/bin/bash

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
	gnome-shell-extension-{dash-to-dock,caffeine} \
	just \
	nss-mdns \
	powertop \
	tuned-ppd \
	fzf \
	glow \
	wl-clipboard \
	gum \
	jetbrains-mono-fonts-all \
	buildah \
	btrfs-progs \
  xhost

# Everything that depends on external repositories should be after this.
# Make sure to set them as disabled and enable them only when you are going to use their packages.
# We do, however, leave crb and EPEL enabled by default.

dnf config-manager --add-repo "https://pkgs.tailscale.com/stable/centos/${MAJOR_VERSION_NUMBER}/tailscale.repo"
dnf config-manager --set-disabled "tailscale-stable"
# FIXME: tailscale EPEL10 request: https://bugzilla.redhat.com/show_bug.cgi?id=2349099
dnf -y --enablerepo "tailscale-stable" install \
	tailscale

dnf -y copr enable ublue-os/packages
dnf -y copr disable ublue-os/packages
dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:packages swap \
	centos-logos bluefin-logos

dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:packages install \
	-x bluefin-logos \
	-x bluefin-readymade-config \
	ublue-os-just \
	ublue-os-luks \
	ublue-os-signing \
	ublue-os-udev-rules \
	ublue-os-update-services \
	ublue-{motd,fastfetch,bling,rebase-helper,setup-services,polkit-rules,brew} \
	uupd \
	bluefin-*

# Upstream ublue-os-signing bug, we are using /usr/etc for the container signing and bootc gets mad at this
# FIXME: remove this once https://github.com/ublue-os/packages/issues/245 is closed
cp -avf /usr/etc/. /etc
rm -rvf /usr/etc

dnf -y copr enable ublue-os/staging
dnf -y copr disable ublue-os/staging
dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:staging install \
	gnome-shell-extension-{appindicator,blur-my-shell,search-light,logo-menu,gsconnect}

dnf -y copr enable che/nerd-fonts "centos-stream-${MAJOR_VERSION_NUMBER}-$(arch)"
dnf -y copr disable che/nerd-fonts
dnf -y --enablerepo "copr:copr.fedorainfracloud.org:che:nerd-fonts" install \
	nerd-fonts

# This is required so homebrew works indefinitely.
# Symlinking it makes it so whenever another GCC version gets released it will break if the user has updated it without-
# the homebrew package getting updated through our builds.
# We could get some kind of static binary for GCC but this is the cleanest and most tested alternative. This Sucks.
dnf -y --setopt=install_weak_deps=False install gcc

if [ "${ENABLE_TESTING}" == "1" ] ; then
	# We need the fedora (LATEST_MAJOR) builds because f41 and el10 namespaces under copr arent customizeable so we cant build using the g48 backport
	# Using the f(LATEST_MAJOR) should provide the dependencies we need just fine.
	FEDORA_MAJOR_SPOOF=42
	dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/ublue-os/staging/repo/fedora-${FEDORA_MAJOR_SPOOF}/ublue-os-staging-fedora-${FEDORA_MAJOR_SPOOF}.repo"
	REPO_FILE="/etc/yum.repos.d/ublue-os-staging-fedora-${FEDORA_MAJOR_SPOOF}.repo"
	sed -i "s/\:staging/&:fedora/" $REPO_FILE
	sed -i "s/\$releasever/$FEDORA_MAJOR_SPOOF/" $REPO_FILE
	dnf config-manager --set-disabled "copr:copr.fedorainfracloud.org:ublue-os:staging:fedora"
	dnf -y \
		--enablerepo "copr:copr.fedorainfracloud.org:ublue-os:staging" \
		--enablerepo "copr:copr.fedorainfracloud.org:ublue-os:staging:fedora" \
		install bazaar
fi
