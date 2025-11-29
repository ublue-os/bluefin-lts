#!/usr/bin/env bash

set -euo pipefail

# Script to build ISO images using the Titanoboa builder
# Usage: build-iso.sh <variant> <flavor> <repo> [hook_script] [flatpaks_list]
#   variant: bluefin, aurora, fedora, centos, etc.
#   flavor: main, dx, gdx (default: main)
#   repo: local, ghcr (default: local)
#   hook_script: optional post_rootfs hook script
#   flatpaks_list: optional flatpaks list file

GITHUB_REPOSITORY_OWNER="${GITHUB_REPOSITORY_OWNER:-ublue-os}"

if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: $(basename "$0") <variant> [flavor] [repo] [hook_script] [flatpaks_list]"
    echo ""
    echo "Arguments:"
    echo "  variant        Image variant (e.g., bluefin, aurora)"
    echo "  flavor         Image flavor (default: main)"
    echo "  repo           Image repository: local or ghcr (default: local)"
    echo "  hook_script    Path to post-rootfs hook script (optional)"
    echo "  flatpaks_list  Path to flatpaks list file (optional)"
    echo ""
    echo "Example:"
    echo "  ./$(basename "$0") bluefin main local"
    exit 0
fi

VARIANT="$1"
FLAVOR="${2:-main}"
REPO="${3:-local}"
HOOK_SCRIPT="${4:-}"
FLATPAKS_LIST="${5:-}"

BUILD_DIR=".build/${VARIANT}-${FLAVOR}"

# Map variants to distros for TITANOBOA_BUILDER_DISTRO
case "$VARIANT" in
    "yellowfin" | "almalinux-kitten" | "almalinux")
        IMAGE_DISTRO="almalinux"
        ;;
    "skipjack" | "centos" | "lts")
        IMAGE_DISTRO="centos"
        ;;
    "bonito" | "fedora" | "bluefin" | "aurora" | "bazzite")
        IMAGE_DISTRO="fedora"
        ;;
    *)
        echo "Unknown variant '$VARIANT', defaulting to fedora builder." >&2
        IMAGE_DISTRO="fedora"
        ;;
esac

# Construct the image URI
if [[ "$FLAVOR" == "main" ]] || [[ "$FLAVOR" == "base" ]]; then
    FLAVOR_SUFFIX=""
else
    FLAVOR_SUFFIX="-$FLAVOR"
fi

# Default tag
TAG="${TAG:-latest}"

if [[ "$REPO" == "ghcr" ]]; then
    IMAGE_NAME="ghcr.io/${GITHUB_REPOSITORY_OWNER}/${VARIANT}${FLAVOR_SUFFIX}:${TAG}"
elif [[ "$REPO" == "local" ]]; then
    IMAGE_NAME="localhost/${VARIANT}${FLAVOR_SUFFIX}:${TAG}"
else
    echo "Unknown repo: $REPO. Use 'local' or 'ghcr'" >&2
    exit 1
fi

echo -e "\n\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;33m                        Building with Titanoboa\033[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "  \033[1;32mVariant:\033[0m       $VARIANT"
echo -e "  \033[1;32mFlavor:\033[0m        $FLAVOR"
echo -e "  \033[1;32mRepo:\033[0m          $REPO"
echo -e "  \033[1;32mImage Distro:\033[0m  $IMAGE_DISTRO"
echo -e "  \033[1;32mImage Name:\033[0m    $IMAGE_NAME"
echo -e "  \033[1;32mHook Script:\033[0m   ${HOOK_SCRIPT:-None}"
echo -e "  \033[1;32mFlatpaks File:\033[0m ${FLATPAKS_LIST:-None}"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n"

# Clean up any previous copy of Titanoboa that might have sudo permissions
if [[ -d "$BUILD_DIR" ]]; then
    echo "Cleaning up previous Titanoboa build directory..."
    sudo rm -rf "$BUILD_DIR"
fi

# Clone Titanoboa
echo "Cloning Titanoboa builder..."
mkdir -p "$(dirname "$BUILD_DIR")"
git clone https://github.com/ublue-os/titanoboa "$BUILD_DIR"

# Prepare arguments for just build
JUST_ARGS=("$IMAGE_NAME")

# Handle Flatpaks
if [[ -n "$FLATPAKS_LIST" ]]; then
    FLATPAKS_LIST=$(realpath -e "$FLATPAKS_LIST")
    echo "Copying flatpaks file to build directory..."
    cp "$FLATPAKS_LIST" "$BUILD_DIR/flatpaks.list"
    JUST_ARGS+=("1" "flatpaks.list")
else
    JUST_ARGS+=("1" "none")
fi

# Handle Hook
HOOK_ENV=""
if [[ -n "$HOOK_SCRIPT" ]]; then
    HOOK_SCRIPT=$(realpath -e "$HOOK_SCRIPT")
    echo "Copying hook script to build directory..."
    cp "$HOOK_SCRIPT" "$BUILD_DIR/hook.sh"
    HOOK_ENV="HOOK_post_rootfs=hook.sh"
fi

# Change to the build directory
pushd "$BUILD_DIR" >/dev/null

# Run the Titanoboa build command
echo "Running Titanoboa build..."
CMD="sudo TITANOBOA_BUILDER_DISTRO=$IMAGE_DISTRO"
if [[ -n "$HOOK_ENV" ]]; then
    CMD="$CMD $HOOK_ENV"
fi
CMD="$CMD just build ${JUST_ARGS[*]}"

echo "Executing: $CMD"
eval "$CMD"

echo "Titanoboa build completed successfully!"

# Move output to workspace output directory
if [[ -f "output.iso" ]]; then
    popd >/dev/null
    mkdir -p output
    ISO_NAME="${VARIANT}-${FLAVOR}-${TAG}.iso"
    mv "$BUILD_DIR/output.iso" "output/$ISO_NAME"
    echo "ISO moved to output/$ISO_NAME"
    
    # Checksum
    pushd output >/dev/null
    sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"
    popd >/dev/null
else
    popd >/dev/null
    echo "Error: output.iso not found."
    exit 1
fi
