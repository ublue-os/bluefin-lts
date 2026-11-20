ARG MAJOR_VERSION="${MAJOR_VERSION:-c10s}"
ARG BASE_IMAGE_SHA="${BASE_IMAGE_SHA:-sha256-feea845d2e245b5e125181764cfbc26b6dacfb3124f9c8d6a2aaa4a3f91082ed}"
ARG ENABLE_HWE="${ENABLE_HWE:-0}"
ARG AKMODS_VERSION="${AKMODS_VERSION:-centos-10}"
ARG WALLPAPERS_IMAGE_REF
ARG BREW_IMAGE_REF
# Upstream mounts akmods-zfs and akmods-nvidia-open; select their tag via AKMODS_VERSION
FROM ghcr.io/ublue-os/akmods-zfs:${AKMODS_VERSION} AS akmods_zfs
# ZFS userspace always comes from the CentOS build. On HWE/GDX the coreos-stable
# userspace is a Fedora build that can need newer libraries than CentOS has.
FROM ghcr.io/ublue-os/akmods-zfs:centos-10@sha256:cbd658bc4e2c84e5bf918a4e58d99c0be00f835cb6c25cf72f2e60523224cfba AS akmods_zfs_userspace
FROM ghcr.io/ublue-os/akmods-nvidia-open:${AKMODS_VERSION} AS akmods_nvidia_open
FROM ${WALLPAPERS_IMAGE_REF} AS wallpapers-src
FROM ${BREW_IMAGE_REF} AS brew

# Wallpapers: same layout and path fix that projectbluefin/common applied
FROM quay.io/centos-bootc/centos-bootc:$MAJOR_VERSION AS wallpapers
COPY --from=wallpapers-src / /out/usr/share
RUN mkdir -p /out/usr/share/backgrounds/bluefin && \
    mv /out/usr/share/*.jxl /out/usr/share/*.xml /out/usr/share/backgrounds/bluefin && \
    sed -i 's|~\/\.local\/share|\/usr\/share|' /out/usr/share/backgrounds/bluefin/*.xml /out/usr/share/gnome-background-properties/*.xml

# ChairLift (Control Center), non-DX images only: the GUI comes from the
# projectbluefin/tap chairlift cask, which brew-preinstall installs at login
# and brew-upgrade keeps current. A cask cannot install root-owned files, so
# the image ships the pkexec helper, its PolicyKit policy and the GSettings
# schemas from the same release. The
# release's checksums.txt is checked against its Sigstore bundle (signed by
# ChairLift's release workflow for exactly this tag) and the archive against
# checksums.txt, so a bump only changes CHAIRLIFT_RELEASE. Same steps as
# projectbluefin/common's Containerfile.
FROM ghcr.io/sigstore/cosign/cosign:v3.1.4@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d AS cosign
FROM quay.io/centos-bootc/centos-bootc:$MAJOR_VERSION AS chairlift
ARG CHAIRLIFT_RELEASE=v26.11.8
ARG TARGETARCH
COPY --from=cosign /ko-app/cosign /usr/local/bin/cosign
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64|arm64) ;; \
      *) echo "no ChairLift release archive for TARGETARCH '${TARGETARCH}'" >&2; exit 1 ;; \
    esac; \
    version="${CHAIRLIFT_RELEASE#v}"; \
    archive="chairlift_${version}_linux_${TARGETARCH}.tar.gz"; \
    install -d /tmp/chairlift-release; \
    cd /tmp/chairlift-release; \
    for asset in checksums.txt checksums.txt.sigstore.json "$archive"; do \
      curl --fail --silent --show-error --location --retry 5 --retry-all-errors --retry-delay 2 \
        --output "$asset" \
        "https://github.com/projectbluefin/chairlift/releases/download/${CHAIRLIFT_RELEASE}/${asset}"; \
    done; \
    # cosign keeps its TUF cache under $HOME; /root is a dangling symlink here.
    HOME=/tmp/chairlift-release cosign verify-blob --bundle checksums.txt.sigstore.json \
      --certificate-identity "https://github.com/projectbluefin/chairlift/.github/workflows/release.yml@refs/tags/${CHAIRLIFT_RELEASE}" \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      checksums.txt; \
    awk -v archive="$archive" 'NF == 2 && $2 == archive' checksums.txt > "$archive.sha256"; \
    if [ "$(wc -l < "$archive.sha256")" -ne 1 ]; then \
      echo "checksums.txt has no single entry for $archive" >&2; exit 1; \
    fi; \
    sha256sum -c "$archive.sha256"; \
    install -d /tmp/chairlift; \
    tar -xzf "$archive" -C /tmp/chairlift \
      chairlift-helper \
      data/io.projectbluefin.chairlift.ublue.policy \
      data/io.projectbluefin.chairlift.livery.gschema.xml \
      data/io.projectbluefin.chairlift.updates.gschema.xml \
      data/io.projectbluefin.chairlift.firstrun.gschema.xml \
      data/io.projectbluefin.chairlift.printers.gschema.xml; \
    policy=/tmp/chairlift/data/io.projectbluefin.chairlift.ublue.policy; \
    grep -qF '<annotate key="org.freedesktop.policykit.exec.path">/usr/bin/chairlift-helper</annotate>' "$policy"; \
    if grep -F 'org.freedesktop.policykit.exec.path' "$policy" | grep -vqF '>/usr/bin/chairlift-helper<'; then \
      echo "ChairLift policy authorizes a helper other than /usr/bin/chairlift-helper" >&2; exit 1; \
    fi; \
    install -Dm0755 /tmp/chairlift/chairlift-helper /out/usr/bin/chairlift-helper; \
    install -Dm0644 "$policy" /out/usr/share/polkit-1/actions/io.projectbluefin.chairlift.ublue.policy; \
    for schema in livery updates firstrun printers; do \
      install -Dm0644 "/tmp/chairlift/data/io.projectbluefin.chairlift.${schema}.gschema.xml" \
        "/out/usr/share/glib-2.0/schemas/io.projectbluefin.chairlift.${schema}.gschema.xml"; \
    done; \
    rm -rf /tmp/chairlift /tmp/chairlift-release

FROM scratch AS context

COPY system_files /files
COPY --from=brew /system_files /files
COPY --from=wallpapers /out /files
COPY system_files_overrides /overrides
COPY --from=chairlift /out /overrides/chairlift
COPY build_scripts /build_scripts

ARG MAJOR_VERSION="${MAJOR_VERSION:-c10s}"
FROM quay.io/centos-bootc/centos-bootc:$MAJOR_VERSION

ARG ENABLE_DX="${ENABLE_DX:-0}"
ARG ENABLE_GDX="${ENABLE_GDX:-0}"
ARG ENABLE_HWE="${ENABLE_HWE:-0}"
# GNOME 50 (jreilly1821/c10s-gnome-50) is the default. GNOME_VERSION=49 still
# builds the pinned GNOME 49 stack as a rollback for one release.
ARG GNOME_VERSION="${GNOME_VERSION:-50}"
ARG IMAGE_NAME="${IMAGE_NAME:-bluefin}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-ublue-os}"
ARG MAJOR_VERSION="${MAJOR_VERSION:-lts}"
ARG SHA_HEAD_SHORT="${SHA_HEAD_SHORT:-deadbeef}"

RUN --mount=type=tmpfs,dst=/opt \
  --mount=type=tmpfs,dst=/tmp \
  --mount=type=tmpfs,dst=/var \
  --mount=type=tmpfs,dst=/boot \
  --mount=type=bind,from=akmods_zfs,src=/rpms,dst=/tmp/akmods-zfs-rpms \
  --mount=type=bind,from=akmods_zfs,src=/kernel-rpms,dst=/tmp/kernel-rpms \
  --mount=type=bind,from=akmods_zfs_userspace,src=/rpms,dst=/tmp/akmods-zfs-userspace-rpms \
  --mount=type=bind,from=akmods_nvidia_open,src=/rpms,dst=/tmp/akmods-nvidia-open-rpms \
  --mount=type=bind,from=context,source=/,target=/run/context \
  /run/context/build_scripts/build.sh

# Makes `/opt` writeable by default
# Needs to be here to make the main image build strict (no /opt there)
RUN rm -rf /opt && ln -s /var/opt /opt 
