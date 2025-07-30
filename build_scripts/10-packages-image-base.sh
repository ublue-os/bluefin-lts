#!/usr/bin/env bash

set -xeuo pipefail

# This is the base for a minimal GNOME system on CentOS Stream.

# This thing slows down downloads A LOT for no reason
dnf remove -y subscription-manager
dnf -y install 'dnf-command(versionlock)'


if [ "${ENABLE_HWE}" == "1" ] ; then
	dnf -y install centos-release-kmods-kernel
	# Install and pin the kernel to the last minor version
	./run/context/build_scripts/scripts/pin-kernel.sh
	dnf config-manager --set-disabled "centos-kmods-kernel"
fi

# GNOME 48 backport COPR
dnf copr enable -y "jreilly1821/c10s-gnome-48"
dnf -y install glib2

# This fixes a lot of skew issues on GDX because kernel-devel wont update then
dnf versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-uki-virt

dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${MAJOR_VERSION_NUMBER}.noarch.rpm"
dnf config-manager --set-enabled crb

# Multimidia codecs
dnf config-manager --add-repo=https://negativo17.org/repos/epel-multimedia.repo
dnf config-manager --set-disabled epel-multimedia
dnf -y install --enablerepo=epel-multimedia \
	ffmpeg libavcodec @multimedia gstreamer1-plugins-{bad-free,bad-free-libs,good,base} lame{,-libs} libjxl ffmpegthumbnailer

# `dnf group info Workstation` without GNOME
dnf group install -y --nobest \
	-x rsyslog* \
	-x cockpit \
	-x cronie* \
	-x crontabs \
	-x PackageKit \
	-x PackageKit-command-not-found \
	"Common NetworkManager submodules" \
	"Core" \
	"Fonts" \
	"Guest Desktop Agents" \
	"Hardware Support" \
	"Printing Client" \
	"Standard" \
	"Workstation product core"

# Minimal GNOME group. ("Multimedia" adds most of the packages from the GNOME group. This should clear those up too.)
# In order to reproduce this, get the packages with `dnf group info GNOME`, install them manually with dnf install and see all the packages that are already installed.
# Other than that, I've removed a few packages we didnt want, those being a few GUI applications.
dnf -y install \
	-x PackageKit \
	-x PackageKit-command-not-found \
	-x gnome-software-fedora-langpacks \
	-x gnome-extensions-app \
	"NetworkManager-adsl" \
	"centos-backgrounds" \
	"gdm" \
	"gnome-bluetooth" \
	"gnome-color-manager" \
	"gnome-control-center" \
	"gnome-initial-setup" \
	"gnome-remote-desktop" \
	"gnome-session-wayland-session" \
	"gnome-settings-daemon" \
	"gnome-shell" \
	"gnome-software" \
	"gnome-user-docs" \
	"gvfs-fuse" \
	"gvfs-goa" \
	"gvfs-gphoto2" \
	"gvfs-mtp" \
	"gvfs-smb" \
	"libsane-hpaio" \
	"nautilus" \
	"orca" \
	"ptyxis" \
	"sane-backends-drivers-scanners" \
	"xdg-desktop-portal-gnome" \
	"xdg-user-dirs-gtk" \
	"yelp-tools"

dnf -y install \
	plymouth \
	plymouth-system-theme \
	fwupd \
	systemd-{resolved,container,oomd} \
	libcamera{,-{v4l2,gstreamer,tools}}

# This package adds "[systemd] Failed Units: *" to the bashrc startup
dnf -y remove console-login-helper-messages
