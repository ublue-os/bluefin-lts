FROM ghcr.io/ublue-os/config:latest@sha256:72c994ea9c6cccf726378afc84ca51598f6dfa93d545e5b7dafc42ce3c04ede9 AS config
FROM ghcr.io/centos-workstation/main:${MAJOR_VERSION:-latest}

ARG IMAGE_NAME="${IMAGE_NAME:-achillobator}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-centos-workstation}"
ARG MAJOR_VERSION="${MAJOR_VERSION:-latest}"
ARG SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-}"

COPY system_files /
COPY build.sh /tmp/build.sh
COPY dx.sh /tmp/dx.sh

RUN --mount=type=bind,from=config,src=/rpms,dst=/tmp/rpms ln -sf /run /var/run && \
    mkdir -p /var/lib/alternatives && \
    /tmp/build.sh && \
    /tmp/dx.sh && \  
    dnf clean all && \
    ostree container commit 

RUN bootc container lint
