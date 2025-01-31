export repo_organization := env("GITHUB_REPOSITORY_OWNER", "ublue-os")
export image_name := env("IMAGE_NAME", "bluefin")
export centos_version := env("CENTOS_VERSION", "stream10")
export default_tag := env("DEFAULT_TAG", "lts")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
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
    #!/usr/bin/bash
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

build $target_image=image_name $tag=default_tag $dx="0" $hwe="0":
    #!/usr/bin/env bash

    # Get Version
    ver="${tag}-${centos_version}.$(date +%Y%m%d)"

    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "MAJOR_VERSION=${centos_version}")
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${image_name}")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR=${repo_organization}")
    BUILD_ARGS+=("--build-arg" "ENABLE_DX=${dx}")
    BUILD_ARGS+=("--build-arg" "ENABLE_HWE=${hwe}")
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi

    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/bash
    set -eoux pipefail

    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi

    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    if [[ $return_code -eq 0 ]]; then
        # Load into Rootful Podman
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ -z "$ID" ]]; then
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        # Make sure the image is present and/or up to date
        just sudoif podman pull "${target_image}:${tag}"
    fi

_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p "output"

    echo "Cleaning up previous build"
    if [[ $type == iso ]]; then
      sudo rm -rf "output/bootiso" || true
    else
      sudo rm -rf "output/${type}" || true
    fi

    args="--type ${type}"

    if [[ $target_image == localhost/* ]]; then
      args+=" --local"
    fi

    sudo podman run \
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
      "${target_image}"

    sudo chown -R $USER:$USER output

_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

[group('Build Virtal Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "qcow2" "image-builder.config.toml")

[group('Build Virtal Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "raw" "image-builder.config.toml")

[group('Build Virtal Machine Image')]
build-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "iso" "image-builder-iso.config.toml")

[group('Build Virtal Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "image-builder.config.toml")

[group('Build Virtal Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "raw" "image-builder.config.toml")

[group('Build Virtal Machine Image')]
rebuild-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "iso" "image-builder-iso.config.toml")

_run-vm $target_image $tag $type $config:
    #!/usr/bin/bash
    set -eoux pipefail

    image_file="output/${type}/disk.${type}"

    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine which port to use
    port=8006;
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    # run_args+=(--env "BOOT_MODE=windows_secure")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu-docker)
    podman run "${run_args[@]}" &
    xdg-open http://localhost:${port}
    fg "%podman"

[group('Run Virtal Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "image-builder.config.toml")

[group('Run Virtal Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "image-builder.config.toml")

[group('Run Virtal Machine')]
run-vm-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "iso" "image-builder-iso.config.toml")

[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6GiB":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "achillobator" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo 6G| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

customize-iso-build:
    sudo podman run \
    --rm -it \
    --privileged \
    --pull=newer \
    --net=host \
    --security-opt label=type:unconfined_t \
    -v $(pwd)/image-builder-iso.config.toml \
    -v $(pwd)/output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    --entrypoint "" \
    "${bib_image}" \
    osbuild --store /store --output-directory /output /output/manifest-iso.json  --export bootiso

patch-iso-branding override="0" iso_path="output/bootiso/install.iso":
    #!/usr/bin/env bash
    podman run \
        --rm \
        -it \
        --pull=newer \
        --privileged \
        -v ./output:/output \
        -v ./iso_files:/iso_files \
        registry.fedoraproject.org/fedora:latest \
        bash -c 'dnf install -y lorax mkksiso && \
    	mkdir /images && cd /iso_files/product && find . | cpio -c -o | gzip -9cv > /images/product.img && cd / \
            && mkksiso --add images --volid achillobator-boot /{{ iso_path }} /output/final.iso'

    if [ {{ override }} -ne 0 ] ; then
        mv output/final.iso {{ iso_path }}
    fi

lint:
    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

format:
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
