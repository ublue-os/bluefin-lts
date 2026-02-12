#!/usr/bin/env bash

set -xeuo pipefail

ARCH=$(uname -m)

# This is the base for a minimal GNOME system on CentOS Stream.

# This thing slows down downloads A LOT for no reason
dnf remove -y subscription-manager
dnf -y install 'dnf-command(versionlock)'

/run/context/build_scripts/scripts/kernel-swap.sh

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
	-x gnome-software \
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

# We need to remove centos-logos before applying bluefin's logos and after installing this package. Do not remove this!
rpm --erase --nodeps centos-logos
# HACK: There currently is no generic-logos equivalent like on Fedora
# We need this so packages like anaconda don't replace our logos by pulling in centos-logos again
dnf -y install https://kojipkgs.fedoraproject.org//packages/generic-logos/18.0.0/26.fc43/noarch/generic-logos-18.0.0-26.fc43.noarch.rpm
rpm --erase --nodeps --nodb generic-logos
