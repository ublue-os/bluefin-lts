#!/bin/bash
ARCH=$(uname -m)
TARGET_MAJOR_MINOR="6.15"
echo "--- Pinning Kernel to ${TARGET_MAJOR_MINOR}.x ---"

rpm -q python3-dnf-plugin-versionlock &> /dev/null || \
    { echo "Installing dnf-plugin-versionlock..."; dnf install -y python3-dnf-plugin-versionlock || { echo "Error: Failed to install versionlock plugin."; exit 1; } }

# Find the newest target kernel version
TARGET_KERNEL_FULL_VERSION=$(dnf list available kernel --showduplicates | \
    grep "^kernel.${ARCH}.*${TARGET_MAJOR_MINOR}\." | \
    awk '{print $2}' | sort -V | tail -n 1)

if [ -z "$TARGET_KERNEL_FULL_VERSION" ]; then
    echo "Error: No ${TARGET_MAJOR_MINOR}.x kernel found. Exiting."
    exit 1
fi

KERNEL_VERSION_ONLY=$(echo "$TARGET_KERNEL_FULL_VERSION" | sed "s/\.${ARCH}$//")
echo "Targeting kernel: ${KERNEL_VERSION_ONLY}"

# Install kernel packages
INSTALL_PKGS=(
    "kernel-${KERNEL_VERSION_ONLY}"
    "kernel-core-${KERNEL_VERSION_ONLY}"
    "kernel-modules-${KERNEL_VERSION_ONLY}"
)
dnf install --allowerasing -y "${INSTALL_PKGS[@]/%/.${ARCH}}" || { echo "Error: Failed to install kernel packages."; exit 1; }
echo "Installing kernel packages: ${INSTALL_PKGS[@]/%/.${ARCH}}"

# Add versionlocks
for pkg in "${INSTALL_PKGS[@]}"; do
    echo "Locking package: ${pkg}.${ARCH}"
    dnf versionlock add "${pkg}.${ARCH}" || { echo "Error: Failed to lock ${pkg}.${ARCH}."; exit 1; }
done

echo "Kernel ${KERNEL_VERSION_ONLY} installed, set as default, and locked."
