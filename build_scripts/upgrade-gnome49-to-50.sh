#!/usr/bin/env bash

set -xeuo pipefail

# Upgrade a GNOME 49 bluefin-lts image to GNOME 50.
# This script is run inside Containerfile.gnome50, which FROMs the GNOME 49
# image. It swaps the COPR, installs the GNOME 50 compat package, and
# upgrades the GNOME stack in place.

MAJOR_VERSION_NUMBER="$(sh -c '. /usr/lib/os-release ; echo ${VERSION_ID%.*}')"

# Swap COPR repos
dnf copr disable -y "jreilly1821/c10s-gnome-49"
dnf copr enable  -y "jreilly1821/c10s-gnome-50"

# selinux-policy 43.x is required for GDM 50 userdb varlink socket architecture.
# EL10 base ships 42.x which lacks the necessary policy rules.
dnf -y install selinux-policy selinux-policy-targeted

# Remove GNOME 49 versionlocks so the upgrade can proceed
dnf versionlock delete gnome-shell gdm gnome-session-wayland-session \
    gobject-introspection gjs pango 2>/dev/null || true

# Swap compat package
dnf -y install gnome50-el10-compat
dnf -y remove  gnome49-el10-compat 2>/dev/null || true

# Upgrade the full GNOME stack to GNOME 50
dnf -y upgrade gnome-shell gdm mutter gnome-session gnome-session-wayland-session \
    gnome-settings-daemon gnome-control-center gsettings-desktop-schemas \
    gtk4 libadwaita pango glib2 gobject-introspection gjs

# Versionlock GNOME 50 components
dnf versionlock add gnome-shell gdm mutter gnome-session-wayland-session \
    gnome-settings-daemon gnome-control-center gsettings-desktop-schemas \
    gtk4 libadwaita pango fontconfig

# Re-compile GLib schemas after upgrading
glib-compile-schemas /usr/share/glib-2.0/schemas/
