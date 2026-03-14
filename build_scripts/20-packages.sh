#!/bin/bash

set -xeuo pipefail

dnf -y remove \
	setroubleshoot

dnf -y install \
	-x gnome-extensions-app \
	NetworkManager-openconnect-gnome \
	NetworkManager-openvpn-gnome \
	btrfs-progs \
	buildah \
	containerd \
	ddcutil \
	distrobox \
	fastfetch \
	firewalld \
	flatpak \
	fpaste \
	fzf \
	glow \
	gnome-disk-utility \
	gum \
	hplip \
	ibus-chewing \
	jetbrains-mono-fonts-all \
	jxl-pixbuf-loader \
	just \
	nss-mdns \
	ntfs-3g \
	papers-thumbnailer \
	pcsc-lite \
	powertop \
	rclone \
	restic \
	system-reinstall-bootc \
	tuned-ppd \
	wireguard-tools \
	wl-clipboard \
	xdg-terminal-exec \
	xhost
rm -rf /usr/share/doc/just

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
dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:packages install uupd

dnf -y copr enable che/nerd-fonts "centos-stream-${MAJOR_VERSION_NUMBER}-$(arch)"
dnf -y copr disable che/nerd-fonts
dnf -y --enablerepo "copr:copr.fedorainfracloud.org:che:nerd-fonts" install \
	nerd-fonts

# This is required so homebrew works indefinitely.
# Symlinking it makes it so whenever another GCC version gets released it will break if the user has updated it without-
# the homebrew package getting updated through our builds.
# We could get some kind of static binary for GCC but this is the cleanest and most tested alternative. This Sucks.
dnf -y --setopt=install_weak_deps=False install gcc

if [[ "${GNOME_VERSION:-49}" == "50" ]]; then
    # Versionlock GNOME 50 components to prevent downgrades to EL10 base versions
    dnf versionlock add gnome-shell gdm mutter gnome-session-wayland-session \
        gnome-settings-daemon gnome-control-center gsettings-desktop-schemas \
        gtk4 libadwaita pango fontconfig
else
    # Versionlock GNOME 49 components to prevent upgrades to a mismatched version
    dnf versionlock add gnome-shell gdm gnome-session-wayland-session gobject-introspection gjs pango
fi

