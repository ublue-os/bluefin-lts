export repo_organization := env("GITHUB_REPOSITORY_OWNER", "projectbluefin")
export image_name := env("IMAGE_NAME", "bluefin")
export centos_version := env("CENTOS_VERSION", "stream10")
export default_tag := env("DEFAULT_TAG", "lts")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")
export coreos_stable_version := env("COREOS_STABLE_VERSION", "")
export HOME := env("HOME", "")
export common_image := env("COMMON_IMAGE", "ghcr.io/projectbluefin/common:latest")
export brew_image := env("BREW_IMAGE", "ghcr.io/ublue-os/brew:latest")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/env bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# This Justfile recipe builds a container image using Podman.
#
# Arguments:
#   $target_image - The tag you want to apply to the image (default: bluefin).
#   $tag - The tag for the image (default: lts).
#   $dx - Enable DX (default: "0").
#   $gdx - Enable GDX (default: "0").
#
# DX:
#   Developer Experience (DX) is a feature that allows you to install the latest developer tools for your system.
#   Packages include VScode, Docker, Distrobox, and more.
# GDX: https://docs.projectbluefin.io/gdx/
#   GPU Developer Experience (GDX) creates a base as an AI and Graphics platform.
#   Installs Nvidia drivers, CUDA, and other tools.
#
# The script constructs the version string using the tag and the current date.
# If the git working directory is clean, it also includes the short SHA of the current HEAD.
#
# just build $target_image $tag $dx $gdx $hwe
#
# Example usage:
#   just build bluefin lts 1 0 1
#
# This will build an image 'bluefin:lts' with DX and HWE enabled.
#

[private]
_ensure-yq:
    #!/usr/bin/env bash
    if ! command -v yq &> /dev/null; then
        echo "Missing requirement: 'yq' is not installed."
        echo "Please install yq (e.g. 'brew install yq')"
        exit 1
    fi

# Build the image using the specified parameters
build $target_image=image_name $tag=default_tag $dx="0" $gdx="0" $hwe="0" $kernel_pin="" $gnome_version="50" $fedora_akmods_version="43": _ensure-yq
    #!/usr/bin/env bash

    # Get Version
    ver="${tag}-${centos_version}.$(date +%Y%m%d)"

    common_image_sha=$(yq -r '.images[] | select(.name == "common") | .digest' image-versions.yaml)
    common_image_ref="${common_image}@${common_image_sha}"
    brew_image_sha=$(yq -r '.images[] | select(.name == "brew") | .digest' image-versions.yaml)
    brew_image_ref="${brew_image}@${brew_image_sha}"

    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "COMMON_IMAGE_REF=${common_image_ref}")
    BUILD_ARGS+=("--build-arg" "BREW_IMAGE_REF=${brew_image_ref}")
    BUILD_ARGS+=("--build-arg" "MAJOR_VERSION=${centos_version}")
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${image_name}")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR=${repo_organization}")
    BUILD_ARGS+=("--build-arg" "ENABLE_DX=${dx}")
    BUILD_ARGS+=("--build-arg" "ENABLE_GDX=${gdx}")
    BUILD_ARGS+=("--build-arg" "ENABLE_HWE=${hwe}")
    BUILD_ARGS+=("--build-arg" "GNOME_VERSION=${gnome_version}")
    # Select akmods source tag for mounted ZFS/NVIDIA images
    ARCH=$(uname -m)
    if [[ "${hwe}" -eq "1" || "${gdx}" -eq "1" ]]; then
        # Dynamically follow Fedora CoreOS stable; override with COREOS_STABLE_VERSION env if set
        if [[ -n "${coreos_stable_version:-}" ]]; then
            coreos_fedora_ver="${coreos_stable_version}"
        else
            coreos_fedora_ver=$(skopeo inspect --retry-times 3 docker://quay.io/fedora/fedora-coreos:stable | jq -r '.Labels["org.opencontainers.image.version"]' | grep -oP '^[0-9]+')
        fi
        AKMODS_BASE="coreos-stable-${coreos_fedora_ver}"
        BUILD_ARGS+=("--build-arg" "FEDORA_AKMODS_VERSION=${coreos_fedora_ver}")
    else
        AKMODS_BASE="centos-10"
        BUILD_ARGS+=("--build-arg" "FEDORA_AKMODS_VERSION=${fedora_akmods_version}")
    fi
    if [[ -n "${kernel_pin}" ]]; then
        BUILD_ARGS+=("--build-arg" "AKMODS_VERSION=${AKMODS_BASE}-${kernel_pin}.${ARCH}")
    else
        BUILD_ARGS+=("--build-arg" "AKMODS_VERSION=${AKMODS_BASE}")
    fi
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi

    echo "Building image ${target_image}:${tag} with args: ${BUILD_ARGS[*]}"
    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Command: _rootful_load_image
# Description: This script checks if the current user is root or running under sudo. If not, it attempts to resolve the image tag using podman inspect.
#              If the image is found, it loads it into rootful podman. If the image is not found, it pulls it from the repository.
#
# Parameters:
#   $target_image - The name of the target image to be loaded or pulled.
#   $tag - The tag of the target image to be loaded or pulled. Default is 'default_tag'.
#
# Example usage:
#   _rootful_load_image my_image latest
#
# Steps:
# 1. Check if the script is already running as root or under sudo.
# 2. Check if target image is in the non-root podman container storage)
# 3. If the image is found, load it into rootful podman using podman scp.
# 4. If the image is not found, pull it from the remote repository into reootful podman.

rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -eoux pipefail

    # Check if already running as root or under sudo
    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi

    # Try to resolve the image tag using podman inspect
    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    if [[ $return_code -eq 0 ]]; then
        # If the image is found, load it into rootful podman
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ -z "$ID" ]]; then
            # If the image ID is not found, copy the image from user podman to root podman
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        # If the image is not found, pull it from the repository
        just sudoif podman pull "${target_image}:${tag}"
    fi

# Build a bootc bootable image using Bootc Image Builder (BIB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: image.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 image.toml
_build-bib $target_image $tag $type $config:
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p "output"

    echo "Cleaning up previous build"
    if [[ $type == iso ]]; then
      sudo rm -rf "output/bootiso" || true
    else
      sudo rm -rf "output/${type}" || true
    fi

    args="--type ${type} "
    args+="--use-librepo=True"

    just sudoif podman run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $(pwd)/output:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${target_image}:${tag}"

    sudo chown -R $USER:$USER output

# Podman build's the image from the Containerfile and creates a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (deafult: image.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 image.toml
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Build a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "qcow2" "image.toml")

# Build a RAW virtual machine image
[group('Build Virtal Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "raw" "image.toml")

# Build an ISO virtual machine image
[group('Build Virtal Machine Image')]
build-iso $target_image=("localhost/" + image_name) $tag=default_tag:
    #!/usr/bin/env bash
    set -eoux pipefail

    # Determine Repo
    REPO="local"
    if [[ "{{ target_image }}" =~ ghcr.io ]]; then
        REPO="ghcr"
    fi

    # Determine Variant
    VARIANT="bluefin"
    if [[ "{{ tag }}" =~ lts ]]; then
        VARIANT="lts"
    fi

    # Determine Flavor
    FLAVOR="base"
    if [[ "{{ target_image }}" =~ -dx ]]; then
        FLAVOR="dx"
    fi
    if [[ "{{ target_image }}" =~ -gdx ]]; then
        FLAVOR="gdx"
    fi

    echo "Delegating to projectbluefin/iso..."
    echo "Variant: $VARIANT"
    echo "Flavor:  $FLAVOR"
    echo "Repo:    $REPO"

    # Clone and Build
    BUILD_ROOT="_iso_build"
    rm -rf "$BUILD_ROOT"
    git clone https://github.com/projectbluefin/iso.git "$BUILD_ROOT"

    pushd "$BUILD_ROOT"
    just local-iso "$VARIANT" "$FLAVOR" "$REPO"
    popd

    # Copy Artifacts
    mv "$BUILD_ROOT"/*.iso .
    rm -rf "$BUILD_ROOT"

# Rebuild a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "image.toml")

# Rebuild a RAW virtual machine image
[group('Build Virtal Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "raw" "image.toml")

# Rebuild an ISO virtual machine image
[group('Build Virtal Machine Image')]
rebuild-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "iso" "iso.toml")

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config $iso_file="":
    #!/usr/bin/env bash
    set -eoux pipefail

    # Determine the image file based on the type
    if [[ -n "$iso_file" ]]; then
        image_file="$iso_file"
    elif [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    else
        image_file="output/${type}/disk.${type}"
    fi

    # Build the image if it does not exist (skip if custom iso_file provided)
    if [[ ! -f "${image_file}" ]]; then
        if [[ -n "$iso_file" ]]; then
            echo "ISO not found at $iso_file. Please build it first or specify a valid ISO path."
            exit 1
        fi
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Web Port: ${port}"
    echo "Connect via Web: http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=4G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)

    # Add SSH port forwarding for all VM types
    ssh_port=$(( port + 1 ))
    while grep -q :${ssh_port} <<< $(ss -tunalp); do
        ssh_port=$(( ssh_port + 1 ))
    done
    echo "Using SSH Port: ${ssh_port}"
    echo "Connect via SSH: ssh user@localhost -p ${ssh_port}"
    run_args+=(--publish "127.0.0.1:${ssh_port}:22")
    run_args+=(--env "USER_PORTS=22")
    run_args+=(--env "NETWORK=user")

    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(ghcr.io/qemus/qemu)

    # Run the VM and open the browser to connect
    (sleep 5 && xdg-open "http://localhost:${port}") &
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtal Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "image.toml")

# Run a virtual machine from a RAW image
[group('Run Virtal Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "image.toml")

# Run a virtual machine from an ISO
[group('Run Virtal Machine')]
run-vm-iso $iso_file="output/bootiso/install.iso": && (_run-vm "" "" "iso" "" iso_file)

# Runs shell check on all Bash scripts
lint:
    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Create a test VM with SSH enabled for debugging/testing
# Create a test VM with SSH enabled for debugging/testing

# Usage: just create-test-vm [name] [tag] [ssh-key]
[group('VM Testing')]
create-test-vm name="bluefin-test-ssh" tag="lts-hwe" ssh_key="":
    @echo "Creating test VM: {{ name }}"
    @if [ -z "{{ ssh_key }}" ]; then ssh_key="{{ HOME }}/.ssh/id_ed25519.pub"; fi
    @./scripts/create-test-vm.sh "{{ name }}" "{{ tag }}" "{{ ssh_key }}"

# Create and immediately start a test VM
[group('VM Testing')]
run-test-vm name="bluefin-test-ssh" tag="lts-hwe":
    @just create-test-vm "{{ name }}" "{{ tag }}" ""
    @echo "Starting VM: {{ name }}"
    @limactl start "{{ name }}"
    @echo "VM is starting. Connect with: limactl shell {{ name }}"

# ── Shared reusable-build.yml compatibility layer ────────────────────────────
# These recipes are called by projectbluefin/actions/.github/workflows/reusable-build.yml
# and must match the interface expected by that workflow.

# Return the OCI image name for a given brand/stream/flavor combination.
# For LTS each variant is its own brand_name so flavor is always "main".
[group('Utility')]
image_name base="bluefin-lts" stream="lts" flavor="main":
    echo "{{ base }}"

# Return the default OCI tag for the given stream (tag == stream for LTS).
[group('Utility')]
generate-default-tag stream="lts" ghcr="0":
    echo "{{ stream }}"

# Return "cache-name allow-cache-write" for the dnf-cache composite action.
[group('Utility')]
setup-cache base="bluefin-lts" stream="lts" ghcr="0" event="push":
    #!/usr/bin/bash
    set -eou pipefail
    ALLOW_CACHE_WRITE="false"
    if [[ "{{ ghcr }}" == "1" ]] && \
       [[ "{{ event }}" == "push" || "{{ event }}" == "workflow_dispatch" || "{{ event }}" == "schedule" ]]; then
        ALLOW_CACHE_WRITE="true"
    fi
    echo "{{ base }}-stream10 ${ALLOW_CACHE_WRITE}"

# Build image for GHCR publication — called with sudo by reusable-build.yml.
# Maps brand_name suffix to ENABLE_HWE / ENABLE_GDX build args.
[group('Image')]
build-ghcr base="bluefin-lts" stream="lts" flavor="main" kernel_pin="":
    #!/usr/bin/bash
    set -eoux pipefail
    if [[ "${UID}" -gt "0" ]]; then
        echo "build-ghcr must run as root (called via sudo -E)" >&2
        exit 1
    fi
    HWE=0
    GDX=0
    [[ "{{ base }}" == *"-hwe"* ]] && HWE=1
    [[ "{{ base }}" == *"gdx"* ]] && GDX=1
    {{ just_executable() }} build "{{ base }}" "{{ stream }}" "0" "${GDX}" "${HWE}" "{{ kernel_pin }}"

# Rechunk image using chunkah (OCI-native, no rpm-ostree).
# Called with sudo by reusable-build.yml for non-testing, non-PR builds.
[group('Image')]
[private]
rechunk base="bluefin-lts" stream="lts" flavor="main" ghcr="0" pipeline="0" previous_build="0":
    #!/usr/bin/bash
    set -eoux pipefail
    IMAGE_NAME="$({{ just_executable() }} image_name {{ base }} {{ stream }} {{ flavor }})"
    DEFAULT_TAG="$({{ just_executable() }} generate-default-tag {{ stream }} {{ ghcr }})"
    IMAGE_REF="localhost/${IMAGE_NAME}:${DEFAULT_TAG}"
    CHUNKAH_VERSION="v0.5.0"
    CHUNKAH_SHA="sha256:352097f3d32186ac11082f8b74cd544678b00388b50c96ba5c8e79503a454fe3"
    CHUNKAH_REF="quay.io/coreos/chunkah:${CHUNKAH_VERSION}@${CHUNKAH_SHA}"
    CONTAINERFILE="build_scripts/Containerfile.splitter"
    CHUNKAH_CONFIG_STR="$(podman inspect "${IMAGE_REF}")"
    buildah build \
        --skip-unused-stages=false \
        --from "${IMAGE_REF}" \
        --build-arg "CHUNKAH=${CHUNKAH_REF}" \
        --build-arg "CHUNKAH_CONFIG_STR=${CHUNKAH_CONFIG_STR}" \
        --build-arg "CHUNKAH_ARGS=--max-layers 128 --prune /sysroot/ --label ostree.commit- --label ostree.final-diffid-" \
        -t "${IMAGE_REF}" \
        -v "$(pwd):/run/src" \
        --security-opt=label=disable \
        "${CONTAINERFILE}"
    rm -f out.ociarchive

# No-op: chunkah rechunk outputs directly to the source tag — no retag needed.
[group('Image')]
[private]
load-rechunk base="bluefin-lts" default_tag="lts" flavor="main":
    echo "LTS: chunkah rechunk is in-place — no retag needed"

# Generate space-separated alias tags (dated + CentOS version aliases for production).
[group('Utility')]
generate-build-tags base="bluefin-lts" tag="lts" flavor="main" kernel_pin="" ghcr="0" version="" github_event="" github_number="":
    #!/usr/bin/bash
    set -eou pipefail
    TODAY="$(date +%Y%m%d)"
    SHA_SHORT="$(git rev-parse --short HEAD)"
    if [[ "{{ github_event }}" == "pull_request" ]]; then
        echo "pr-{{ github_number }}-{{ tag }}-${TODAY} ${SHA_SHORT}-{{ tag }}-${TODAY}"
        exit 0
    fi
    TAGS=("{{ tag }}-${TODAY}" "{{ tag }}.${TODAY}")
    if [[ "{{ tag }}" != "testing" ]]; then
        CNOS="$(echo "{{ centos_version }}" | tr -cd '0-9')"
        TAGS+=("stream${CNOS}" "stream${CNOS}-${TODAY}" "${CNOS}" "${CNOS}-${TODAY}")
    fi
    echo "${TAGS[*]}"

# Apply alias tags to the local image.
[group('Utility')]
tag-images image_name="" default_tag="" tags="":
    #!/usr/bin/bash
    set -eou pipefail
    IMAGE=$(podman inspect "localhost/{{ image_name }}:{{ default_tag }}" | jq -r '.[].Id')
    for tag in {{ tags }}; do
        podman tag "${IMAGE}" "{{ image_name }}:${tag}"
    done
    podman images

# Generate SBOM for the built image using syft.
[group('Utility')]
gen-sbom base="bluefin-lts" stream="lts" flavor="main" syft_cmd="syft":
    #!/usr/bin/bash
    set -eou pipefail
    IMAGE_NAME="$({{ just_executable() }} image_name {{ base }} {{ stream }} {{ flavor }})"
    DEFAULT_TAG="$({{ just_executable() }} generate-default-tag {{ stream }} 1)"
    mkdir -p "sbom_out/${IMAGE_NAME}"
    OCI_DIR="sbom_out/${IMAGE_NAME}/oci-dir"
    podman save --format oci-dir -o "${OCI_DIR}" "localhost/${IMAGE_NAME}:${DEFAULT_TAG}"
    {{ syft_cmd }} "oci-dir:${OCI_DIR}" \
        -o syft-json="sbom_out/${IMAGE_NAME}/sbom.json"

# Secureboot validation stub — LTS uses bootc + TPM2/Verity, not UKI.
[group('Utility')]
secureboot base="bluefin-lts" tag="lts" flavor="main":
    echo "Secureboot check: LTS is CentOS bootc-based (TPM2/Verity). UKI check not applicable."
