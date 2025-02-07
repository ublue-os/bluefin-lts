ARG MAJOR_VERSION="${MAJOR_VERSION:-stream10}"
FROM ghcr.io/astral-sh/uv:latest@sha256:88d7b48fc9f17462c82b5482e497af250d337f3f14e1ac97c16e68eba49b651e AS uv-bin
FROM ghcr.io/ublue-os/config:latest@sha256:9dce9d52ba90b418d768a65486c30be9fcf4b4f54ceb787602be6776b749ba88 AS config
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
COPY --from=uv-bin /uv* /var/tmp/system_files_overrides/dx/usr/bin

RUN --mount=type=tmpfs,dst=/tmp --mount=type=bind,from=config,src=/rpms,dst=/tmp/rpms /var/tmp/build_scripts/build.sh
