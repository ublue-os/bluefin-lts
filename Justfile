# Environment Variables
export repo_organization := env("GITHUB_REPOSITORY_OWNER", "ublue-os")
export image_name := env("IMAGE_NAME", "bluefin")
export centos_version := env("CENTOS_VERSION", "stream10")
export default_tag := env("DEFAULT_TAG", "lts")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")
export coreos_stable_version := env("COREOS_STABLE_VERSION", "42")

[private]
default:
    @just --list

# === Just Syntax Management ===

# Check Just syntax in all files
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" -exec sh -c 'echo "Checking: $1" && just --unstable --fmt --check -f "$1"' _ {} \;
    echo "Checking: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just syntax in all files
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" -exec sh -c 'echo "Fixing: $1" && just --unstable --fmt -f "$1"' _ {} \;
    echo "Fixing: Justfile"
    just --unstable --fmt -f Justfile

# === Utility Commands ===

# Clean build artifacts
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -eoux pipefail
    find . -name "*_build*" -exec rm -rf {} + 2>/dev/null || true
    rm -f previous.manifest.json changelog.md output.env

# Clean with sudo privileges
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# Execute command with sudo if needed
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/env bash
    sudoif() {
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif command -v sudo >/dev/null; then
            if [[ -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
                sudo --askpass "$@"
            else
                sudo "$@"
            fi
        else
            echo "Error: sudo not available and not running as root" >&2
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# === Container Image Build ===

# Build container image
# Arguments: target_image, tag, dx (Developer Experience), gdx (GPU DX), hwe (Hardware Enablement)
# Example: just build bluefin lts 1 0 1
[group('Build')]
build target_image=image_name tag=default_tag dx="0" gdx="0" hwe="0":
    #!/usr/bin/env bash
    set -euo pipefail
    
    ver="${tag}-${centos_version}.$(date +%Y%m%d)"
    
    BUILD_ARGS=(
        "--build-arg" "MAJOR_VERSION=${centos_version}"
        "--build-arg" "IMAGE_NAME=${image_name}"
        "--build-arg" "IMAGE_VENDOR=${repo_organization}"
        "--build-arg" "ENABLE_DX=${dx}"
        "--build-arg" "ENABLE_GDX=${gdx}"
        "--build-arg" "ENABLE_HWE=${hwe}"
    )
    
    # Select akmods version based on HWE flag
    if [[ "${hwe}" -eq "1" ]]; then
        BUILD_ARGS+=("--build-arg" "AKMODS_VERSION=coreos-stable-${coreos_stable_version}")
    else
        BUILD_ARGS+=("--build-arg" "AKMODS_VERSION=centos-10")
    fi
    
    # Add git SHA if working directory is clean
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    
    echo "Building ${target_image}:${tag}"
    just sudoif podman build "${BUILD_ARGS[@]}" --pull=newer --tag "${target_image}:${tag}" .

# Build ISO using Titanoboa
# Usage: just build-iso <variant> <flavor>
# Example: just build-iso bluefin main
[group('Build')]
iso variant="bluefin" flavor="main" hooks="" flatpaks="":
    #!/usr/bin/env bash
    set -euo pipefail
    
    if [[ "{{ hooks }}" == "" ]]; then
        HOOK_URL="https://raw.githubusercontent.com/ublue-os/bluefin/refs/heads/main/iso_files/configure_lts_iso_anaconda.sh"
        echo "Downloading hook script..."
        curl -sL "$HOOK_URL" -o "$TMP_DIR/hook.sh"
        HOOK_PATH="$TMP_DIR/hook.sh"
    else
        HOOK_PATH="{{ hooks }}"
    fi
    
    if [[ "{{ flatpaks }}" == "" ]]; then
        FLATPAKS_URL="https://raw.githubusercontent.com/ublue-os/bluefin/refs/heads/main/flatpaks/system-flatpaks.list"
        echo "Downloading flatpak list..."
        curl -sL "$FLATPAKS_URL" -o "$TMP_DIR/flatpaks.list"
        FLATPAKS_PATH="$TMP_DIR/flatpaks.list"
    else
        FLATPAKS_PATH="{{ flatpaks }}"  
    fi

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    
    # Run the build script
    # We use TAG=lts because this is the bluefin-lts repo
    export TAG="lts"
    ./build-iso.sh "{{ variant }}" "{{ flavor }}" "ghcr" "${HOOK_PATH}" "${FLATPAKS_PATH}"

# Load image into rootful podman
[group('Build')]
[private]
rootful_load_image target_image=image_name tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Skip if already root
    [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]] && exit 0
    
    # Check if image exists locally
    if podman inspect -t image "${target_image}:${tag}" &>/dev/null; then
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ -z "$ID" ]]; then
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        just sudoif podman pull "${target_image}:${tag}"
    fi

# === VM Image Build (Internal) ===

[private]
_build-bib target_image tag image_type="qcow2" config="image.toml":
    #!/usr/bin/env bash
    set -euo pipefail
    
    mkdir -p output
    
    # Clean previous build
    if [[ "{{ image_type }}" == "iso" ]]; then
        sudo rm -rf output/bootiso || true
    else
        sudo rm -rf "output/{{ image_type }}" || true
    fi
    
    args="--type {{ image_type }} --use-librepo=True"
    [[ "{{ target_image }}" == localhost/* ]] && args+=" --local"
    
    just sudoif podman run \
        --rm -it --privileged --pull=newer --net=host \
        --security-opt label=type:unconfined_t \
        -v "$(pwd)/{{ config }}:/config.toml:ro" \
        -v "$(pwd)/output:/output" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "{{ bib_image }}" ${args} "{{ target_image }}:{{ tag }}"
    
    sudo chown -R $USER:$USER output

[private]
_rebuild-bib target_image tag image_type config: (build target_image tag) && (_build-bib target_image tag image_type config)

# === VM Image Build Commands ===

# Build virtual machine image (qcow2, raw, or iso)
[group('VM Build')]
build-vm target_image=("localhost/" + image_name) tag=default_tag image_type="qcow2":
    #!/usr/bin/env bash
    set -euo pipefail
    config="image.toml"
    [[ "{{ image_type }}" == "iso" ]] && config="iso.toml"
    just _build-bib "{{ target_image }}" "{{ tag }}" "{{ image_type }}" "$config"

# Rebuild virtual machine image (includes container build)
[group('VM Build')]
rebuild-vm target_image=("localhost/" + image_name) tag=default_tag image_type="qcow2": (build target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail
    config="image.toml"
    [[ "{{ image_type }}" == "iso" ]] && config="iso.toml"
    just _build-bib "{{ target_image }}" "{{ tag }}" "{{ image_type }}" "$config"

# === VM Runtime ===

# Run virtual machine (qcow2, raw, or iso)
[group('VM Run')]
run-vm target_image=("localhost/" + image_name) tag=default_tag image_type="qcow2":
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Determine image file path and config
    if [[ "{{ image_type }}" == "iso" ]]; then
        image_file="output/bootiso/install.iso"
        config="iso.toml"
    else
        image_file="output/{{ image_type }}/disk.{{ image_type }}"
        config="image.toml"
    fi
    
    # Build if doesn't exist
    [[ ! -f "${image_file}" ]] && just build-vm "{{ target_image }}" "{{ tag }}" "{{ image_type }}"
    
    # Find available port
    port=8006
    while ss -tunalp 2>/dev/null | grep -q ":${port}"; do
        ((port++))
    done
    
    echo "Starting VM on http://localhost:${port}"
    
    # Run VM with QEMU
    just sudoif podman run --rm --privileged --pull=newer \
        -p "127.0.0.1:${port}:8006" \
        -e CPU_CORES=4 -e RAM_SIZE=4G -e DISK_SIZE=64G \
        -e TPM=Y -e GPU=Y \
        --device=/dev/kvm \
        -v "${PWD}/${image_file}:/boot.{{ image_type }}" \
        docker.io/qemux/qemu &
    
    sleep 2
    xdg-open "http://localhost:${port}"
    fg || true

# === Code Quality ===

# Run shellcheck on all bash scripts
[group('Quality')]
lint:
    find . -iname "*.sh" -type f -exec shellcheck {} +

# Format all bash scripts with shfmt
[group('Quality')]
format:
    find . -iname "*.sh" -type f -exec shfmt --write {} +

# === Testing Pipelines ===

# Test locally built image: build container -> build qcow2 -> run VM
[group('Test')]
test-local variant="lts":
    #!/usr/bin/env bash
    set -euo pipefail
    
    dx="0"
    gdx="0"
    hwe="0"
    tag="lts"
    
    case "{{ variant }}" in
        hwe)
            hwe="1"
            tag="lts-hwe"
            ;;
        gdx)
            gdx="1"
            tag="lts-gdx"
            ;;
        lts)
            tag="lts"
            ;;
        *)
            echo "Unknown variant: {{ variant }}"
            echo "Valid options: lts, hwe, gdx"
            exit 1
            ;;
    esac
    
    echo "Testing local build: variant={{ variant }}, tag=${tag}"
    just build "localhost/${image_name}" "${tag}" "${dx}" "${gdx}" "${hwe}"
    just build-vm "localhost/${image_name}" "${tag}" "qcow2"
    just run-vm "localhost/${image_name}" "${tag}" "qcow2"

# Test GHCR image: pull from registry -> build qcow2 -> run VM
[group('Test')]
test variant="lts":
    #!/usr/bin/env bash
    set -euo pipefail
    
    tag="lts"
    
    case "{{ variant }}" in
        hwe)
            tag="lts-hwe"
            ;;
        gdx)
            tag="lts-gdx"
            ;;
        lts)
            tag="lts"
            ;;
        *)
            echo "Unknown variant: {{ variant }}"
            echo "Valid options: lts, hwe, gdx"
            exit 1
            ;;
    esac
    
    image="ghcr.io/${repo_organization}/${image_name}"
    
    echo "Testing GHCR image: variant={{ variant }}, tag=${tag}"
    echo "Pulling ${image}:${tag}"
    just sudoif podman pull "${image}:${tag}"
    just build-vm "${image}" "${tag}" "qcow2"
    just run-vm "${image}" "${tag}" "qcow2"