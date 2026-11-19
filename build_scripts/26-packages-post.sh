#!/usr/bin/env bash

set -xeuo pipefail

# Fancy CentOS icon on the fastfetch
sed -i "s/󰣛//g" /usr/share/ublue-os/fastfetch.jsonc

# Automatic wallpaper changing by month
HARDCODED_RPM_MONTH="12"
sed -i "/picture-uri/ s/${HARDCODED_RPM_MONTH}/$(date +%m)/" "/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override"
glib-compile-schemas /usr/share/glib-2.0/schemas

# November wallpaper: the wallpapers image ships 11-bluefin.xml without its SVGs (same workaround as Bluefin)
ARTWORK_URL="https://raw.githubusercontent.com/projectbluefin/artwork/f784bbe296ca224b70058807b3c6cb180516ac84/wallpapers/11-bluefin"
curl -fsSL --retry 3 -o /tmp/11-bluefin-day.svg "${ARTWORK_URL}/11-bluefin-day.svg"
curl -fsSL --retry 3 -o /tmp/11-bluefin-night.svg "${ARTWORK_URL}/11-bluefin-night.svg"
echo "7833a5c6ff095998551f564704597e786849fd5f4367947b47968681b01c218a  /tmp/11-bluefin-day.svg" | sha256sum -c -
echo "deab0feafa53c1c215165e6513431d5832a81f9aefdea2372265e85b26512d51  /tmp/11-bluefin-night.svg" | sha256sum -c -
install -Dm0644 -t /usr/share/backgrounds/bluefin/ /tmp/11-bluefin-day.svg /tmp/11-bluefin-night.svg
# The Settings picker entry (gnome-background-properties/11-bluefin.xml) names these two
ln -sf 11-bluefin-day.svg /usr/share/backgrounds/bluefin/11-bluefin.svg
ln -sf 11-bluefin-night.svg /usr/share/backgrounds/bluefin/11-bluefin-dark.svg

# Rebuild gdk-pixbuf loader cache so all installed loaders are registered
gdk-pixbuf-query-loaders-64 --update-cache

# Offline Bluefin documentation
curl --retry 3 -Lo /tmp/bluefin.pdf https://github.com/ublue-os/bluefin-docs/releases/download/0.1/bluefin.pdf
install -Dm0644 -t /usr/share/doc/bluefin/ /tmp/bluefin.pdf

# Add Flathub by default
mkdir -p /etc/flatpak/remotes.d
curl --retry 3 -o /etc/flatpak/remotes.d/flathub.flatpakrepo "https://dl.flathub.org/repo/flathub.flatpakrepo"

# There is no `-defaults` subpackage on c10s
curl -fsSLo /usr/lib/systemd/zram-generator.conf "https://src.fedoraproject.org/rpms/zram-generator/raw/rawhide/f/zram-generator.conf"
grep -F -e "zram-size =" /usr/lib/systemd/zram-generator.conf

# https://src.fedoraproject.org/rpms/firewalld/blob/rawhide/f/firewalld.spec
curl -fsSLo /usr/lib/firewalld/zones/FedoraWorkstation.xml "https://src.fedoraproject.org/rpms/firewalld/raw/rawhide/f/FedoraWorkstation.xml"
grep -F -e '<port protocol="udp" port="1025-65535"/>' /usr/lib/firewalld/zones/FedoraWorkstation.xml

# https://src.fedoraproject.org/rpms/firewalld/blob/rawhide/f/firewalld.spec#_178
sed -i 's|^DefaultZone=.*|DefaultZone=FedoraWorkstation|g' /etc/firewalld/firewalld.conf
sed -i 's|^IPv6_rpfilter=.*|IPv6_rpfilter=loose|g' /etc/firewalld/firewalld.conf
grep -F -e "DefaultZone=FedoraWorkstation" /etc/firewalld/firewalld.conf
grep -F -e "IPv6_rpfilter=loose" /etc/firewalld/firewalld.conf

# firewalld (FirewallBackend=nftables) and rootful podman (netavark) both need a
# working libnftables. Fail the build if nftables doesn't match libnftnl.
nft --version
python3 -c 'import nftables; nftables.Nftables()'

depmod -a "$(ls -1 /lib/modules/ | tail -1)"

# Generate initramfs image after installing Bluefin branding because of Plymouth subpackage
# Add resume module so that hibernation works
echo "add_dracutmodules+=\" resume \"" >/etc/dracut.conf.d/resume.conf
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//' | tail -n 1)"
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --tmpdir /boot --zstd -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

# The kernel execs CONFIG_MODPROBE_PATH for every kernel-side module autoload
# (dm-crypt when unlocking LUKS, filesystems, nftables, crypto). Fedora kernels
# (HWE/GDX) expect /usr/bin/modprobe, which CentOS doesn't ship; kernel-swap.sh
# links it. Fail the build if that path is missing from the image or initramfs.
KERNEL_MODPROBE_PATH="$(sed -n 's/^CONFIG_MODPROBE_PATH="\(.*\)"$/\1/p' "/lib/modules/$QUALIFIED_KERNEL/config")"
if [[ -n "${KERNEL_MODPROBE_PATH}" ]]; then
    if [[ ! -x "${KERNEL_MODPROBE_PATH}" ]]; then
        echo "FATAL: kernel ${QUALIFIED_KERNEL} expects modprobe at ${KERNEL_MODPROBE_PATH}, which is not in the image"
        exit 1
    fi
    INITRD_MODPROBE="$(readlink -f "$(dirname "${KERNEL_MODPROBE_PATH}")")/$(basename "${KERNEL_MODPROBE_PATH}")"
    INITRD_FILES="$(lsinitrd "/lib/modules/$QUALIFIED_KERNEL/initramfs.img")"
    if ! grep -qE " ${INITRD_MODPROBE#/}( |$)" <<<"${INITRD_FILES}"; then
        echo "FATAL: initramfs for ${QUALIFIED_KERNEL} has no ${INITRD_MODPROBE}"
        exit 1
    fi
fi

# HWE/GDX: kernel-swap.sh installs xone, openrazer and v4l2loopback from the
# ublue-os/akmods image. Fail the build if one of them is missing or was built
# for another kernel, so a change in that image cannot drop them silently.
if [[ "${ENABLE_HWE:-0}" -eq 1 || "${ENABLE_GDX:-0}" -eq 1 ]]; then
    # One module from each package. akmods has no openrazer build for aarch64.
    COMMON_KMODS=(xone_gip v4l2loopback)
    if [[ "$(uname -m)" == "x86_64" ]]; then
        COMMON_KMODS+=(razerkbd)
    fi
    for kmod in "${COMMON_KMODS[@]}"; do
        KMOD_FILE="$(modinfo -k "$QUALIFIED_KERNEL" -F filename "$kmod")" || {
            echo "FATAL: kernel module ${kmod} is not installed for ${QUALIFIED_KERNEL}"
            exit 1
        }
        KMOD_VERMAGIC="$(modinfo -k "$QUALIFIED_KERNEL" -F vermagic "$kmod")"
        if [[ "${KMOD_FILE}" != "/lib/modules/${QUALIFIED_KERNEL}/extra/"* || "${KMOD_VERMAGIC%% *}" != "${QUALIFIED_KERNEL}" ]]; then
            echo "FATAL: kernel module ${kmod} (${KMOD_FILE}, vermagic ${KMOD_VERMAGIC}) does not match ${QUALIFIED_KERNEL}"
            exit 1
        fi
    done
fi
