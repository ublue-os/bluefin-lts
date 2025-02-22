#!/usr/bin/env bash

VEN_ID="$(cat /sys/devices/virtual/dmi/id/chassis_vendor)"

# Ensure custom ptyxis theme is present
PTYXIS_THEME_DIR="/etc/skel/.local/share/org.gnome.Ptyxis/palettes"
PTYXIS_DIR="$HOME/.local/share/org.gnome.Ptyxis/palettes"
mkdir -p "$PTYXIS_DIR"
if [[ ! -f "$PTYXIS_DIR/catppuccin-dynamic.palette" ]]; then
	cp "$PTYXIS_THEME_DIR/catppuccin-dynamic.palette" "$PTYXIS_DIR/catppuccin-dynamic.palette"
fi

UBLUE_CONFIG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ublue"
mkdir -p "$UBLUE_CONFIG_DIR"

if [[ ":Framework:" =~ :$VEN_ID: ]]; then
	if [[ ! -f "$UBLUE_CONFIG_DIR/framework-initialized" ]]; then
		echo 'Setting Framework logo menu'
		dconf write /org/gnome/shell/extensions/Logo-menu/symbolic-icon true
		dconf write /org/gnome/shell/extensions/Logo-menu/menu-button-icon-image 31
		echo 'Setting touch scroll type'
		dconf write /org/gnome/desktop/peripherals/mouse/natural-scroll true
		if [[ $SYS_ID == "Laptop ("* ]]; then
			echo 'Applying font fix for Framework 13'
			dconf write /org/gnome/desktop/interface/text-scaling-factor 1.25
		fi
		touch "$UBLUE_CONFIG_DIR/framework-initialized"
	fi
fi
