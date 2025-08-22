#!/bin/bash
ARCH=$(uname -m)

# Fetch the kernel version from Bluefin Stable
file_content=$(curl -s https://raw.githubusercontent.com/ublue-os/bluefin/refs/heads/main/.github/workflows/build-image-stable.yml)
TARGET_MAJOR_MINOR_MINOR=$(echo "$file_content" | grep -oP 'kernel_pin: \K\d+\.\d+\.\d+')

echo "--- Pinning Kernel to ${TARGET_MAJOR_MINOR_MINOR} ---"

BASE_URL="https://cbs.centos.org/kojifiles/packages/kernel/${TARGET_MAJOR_MINOR_MINOR}/1.el10/${ARCH}"
PKGS_URLS=(
    "${BASE_URL}/kernel-${TARGET_MAJOR_MINOR_MINOR}-1.el10.${ARCH}.rpm"
    "${BASE_URL}/kernel-core-${TARGET_MAJOR_MINOR_MINOR}-1.el10.${ARCH}.rpm"
    "${BASE_URL}/kernel-modules-${TARGET_MAJOR_MINOR_MINOR}-1.el10.${ARCH}.rpm"
    "${BASE_URL}/kernel-headers-${TARGET_MAJOR_MINOR_MINOR}-1.el10.${ARCH}.rpm"
)

dnf uninstall -y kernel-uki-virt
dnf install --allowerasing -y "${PKGS_URLS[@]}" || { echo "Error: Failed to install kernel packages."; exit 1; }

# Add versionlocks
dnf install -y 'dnf-command(versionlock)'

KERNEL_VERSION_ONLY=$(echo "${PKGS_URLS[0]}" | sed -E "s/^.*kernel-|-\.[0-9]+\.el[0-9]+\.${ARCH}\.rpm$//")
echo "Targeting kernel: ${KERNEL_VERSION_ONLY}"

# Add versionlocks
for pkg_url in "${PKGS_URLS[@]}"; do
    # Extract the package name and version from the URL
    pkg_name=$(basename "$pkg_url" | sed -E "s/\\.${ARCH}\\.rpm$//")
    echo "Locking package: ${pkg_name}"
    dnf versionlock add "${pkg_name}" || { echo "Error: Failed to lock ${pkg_name}."; exit 1; }
done

echo "Kernel ${KERNEL_VERSION_ONLY} installed and locked."
rpm -qa | grep 'kernel.*'
