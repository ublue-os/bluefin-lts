#!/usr/bin/env bash

set -xeuo pipefail

IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"
IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_FLAVOR="main"
IMAGE_TAG="lts"
if [ "${ENABLE_HWE}" == "1" ] ; then
IMAGE_TAG="${IMAGE_TAG}-hwe"
fi

cat >$IMAGE_INFO <<EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-ref": "${IMAGE_REF}",
  "image-flavor": "${IMAGE_FLAVOR}",
  "image-vendor": "${IMAGE_VENDOR}",
  "image-tag": "${IMAGE_TAG}",
  "centos-version": "${MAJOR_VERSION_NUMBER}"
}
EOF

OLD_PRETTY_NAME="$(sh -c '. /usr/lib/os-release ; echo $NAME $VERSION')"
IMAGE_PRETTY_NAME="Bluefin LTS"
HOME_URL="https://projectbluefin.io"
DOCUMENTATION_URL="https://docs.projectbluefin.io"
SUPPORT_URL="https://github.com/ublue-os/bluefin-lts/issues/"
BUG_SUPPORT_URL="https://github.com/ublue-os/bluefin-lts/issues/"
CODE_NAME="Achillobator"

# OS Release File (changed in order with upstream)
sed -i -f - /usr/lib/os-release <<EOF
s/^NAME=.*/NAME=\"${IMAGE_PRETTY_NAME}\"/
s|^VERSION_CODENAME=.*|VERSION_CODENAME=\"${CODE_NAME}\"|
s/^VARIANT_ID=.*/VARIANT_ID=${IMAGE_NAME}/
s/^PRETTY_NAME=.*/PRETTY_NAME=\"${IMAGE_PRETTY_NAME}\"/
s|^HOME_URL=.*|HOME_URL=\"${HOME_URL}\"|
s|^BUG_REPORT_URL=.*|BUG_REPORT_URL=\"${BUG_SUPPORT_URL}\"|
s|^CPE_NAME=\"cpe:/o:centos:centos|CPE_NAME=\"cpe:/o:universal-blue:bluefin-lts|

/^REDHAT_BUGZILLA_PRODUCT=/d
/^REDHAT_BUGZILLA_PRODUCT_VERSION=/d
/^REDHAT_SUPPORT_PRODUCT=/d
/^REDHAT_SUPPORT_PRODUCT_VERSION=/d
EOF

tee -a /usr/lib/os-release <<EOF
DOCUMENTATION_URL="${DOCUMENTATION_URL}"
SUPPORT_URL="${SUPPORT_URL}"
DEFAULT_HOSTNAME="bluefin"
BUILD_ID="${SHA_HEAD_SHORT:-deadbeef}"
EOF

# Weekly user count for fastfetch
curl --retry 3 https://raw.githubusercontent.com/ublue-os/countme/main/badge-endpoints/bluefin-lts.json | jq -r ".message" > /usr/share/ublue-os/fastfetch-user-count

# bazaar weekly downloads used for fastfetch
curl -X 'GET' \
'https://flathub.org/api/v2/stats/io.github.kolunmi.Bazaar?all=false&days=1' \
-H 'accept: application/json' | jq -r ".installs_last_7_days" | numfmt --to=si --round=nearest > /usr/share/ublue-os/bazaar-install-count
