ARG MAJOR_VERSION="${MAJOR_VERSION:-c10s}"
ARG BASE_IMAGE_SHA="${BASE_IMAGE_SHA:-sha256-feea845d2e245b5e125181764cfbc26b6dacfb3124f9c8d6a2aaa4a3f91082ed}"
FROM scratch as context

COPY system_files /files
COPY system_files_overrides /overrides
COPY build_scripts /build_scripts

ARG MAJOR_VERSION="${MAJOR_VERSION:-c10s}"
FROM quay.io/centos-bootc/centos-bootc:$MAJOR_VERSION

ARG ENABLE_DX="${ENABLE_DX:-0}"
ARG ENABLE_GDX="${ENABLE_GDX:-0}"
ARG ENABLE_HWE="${ENABLE_HWE:-0}"
ARG IMAGE_NAME="${IMAGE_NAME:-bluefin}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-ublue-os}"
ARG MAJOR_VERSION="${MAJOR_VERSION:-lts}"
ARG SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-deadbeef}"

RUN --mount=type=tmpfs,dst=/opt \
  --mount=type=tmpfs,dst=/tmp \
  --mount=type=tmpfs,dst=/var \
  --mount=type=tmpfs,dst=/boot \
  --mount=type=bind,from=context,source=/,target=/run/context \
  /run/context/build_scripts/build.sh

# Makes `/opt` writeable by default
# Needs to be here to make the main image build strict (no /opt there)
RUN rm -rf /opt && ln -s /var/opt /opt 
