ARG MAJOR_VERSION="${MAJOR_VERSION:-stream10}"
FROM ghcr.io/astral-sh/uv:latest@sha256:01ddc2a91588f1210396433c79c9f58848ad668ea05bda895f5a1a31f2e5b64f AS uv-bin
FROM ghcr.io/ublue-os/config:latest@sha256:17e271e96f3b4dc4214b45552f533c130d405601a64a45561fe109bc1503d12a AS config
FROM quay.io/centos-bootc/centos-bootc:$MAJOR_VERSION

# ARM should be handled by $(arch)
ARG ENABLE_DX="${ENABLE_DX:-0}"
ARG ENABLE_HWE="${ENABLE_HWE:-0}"
ARG ENABLE_GDX="${ENABLE_GDX:-0}"
ARG IMAGE_NAME="${IMAGE_NAME:-bluefin}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-ublue-os}"
ARG MAJOR_VERSION="${MAJOR_VERSION:-lts}"
ARG SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-}"

COPY system_files /
COPY system_files_overrides /var/tmp/system_files_overrides
COPY build_scripts /var/tmp/build_scripts
# FIXME: install UV from EPEL whenever it gets released there, its currently on epel-testing but its broken (07-02-2025)
COPY --from=uv-bin /uv* /var/tmp/system_files_overrides/x86-64-gdx/usr/bin

RUN --mount=type=tmpfs,dst=/tmp --mount=type=bind,from=config,src=/rpms,dst=/tmp/rpms /var/tmp/build_scripts/build.sh
