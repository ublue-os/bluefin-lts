ARG MAJOR_VERSION="${MAJOR_VERSION:-stream10}"
ARG BASE_IMAGE_SHA="sha256-feea845d2e245b5e125181764cfbc26b6dacfb3124f9c8d6a2aaa4a3f91082ed"

#FROM quay.io/centos-bootc/centos-bootc:$MAJOR_VERSION
FROM quay.io/centos-bootc/centos-bootc:$BASE_IMAGE_SHA

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

RUN --mount=type=tmpfs,dst=/tmp /var/tmp/build_scripts/build.sh
