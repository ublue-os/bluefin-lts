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
	just \
	libgda-sqlite \
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

# Downgrade to GNOME 48 from jreilly1821/c10s-gnome-48 COPR
# This pins us to gnome-shell 48.x instead of the upstream 49.x
dnf -y copr enable jreilly1821/c10s-gnome-48
dnf -y copr disable jreilly1821/c10s-gnome-48
dnf -y --enablerepo copr:copr.fedorainfracloud.org:jreilly1821:c10s-gnome-48 swap gnome-shell gnome-shell-48.3 --allowerasing
# Versionlock GNOME components to prevent upgrades back to 49
dnf -y install python3-dnf-plugin-versionlock
dnf versionlock add gnome-shell gdm gnome-session-wayland-session
