#!/bin/bash

set -xeuo pipefail

# This is a bucket list. We want to not have anything in this file at all.

# Enable the same compose repos during our build that the centos-bootc image
# uses during its build.  This avoids downgrading packages in the image that
# have strict NVR requirements.
#
# If the pinned compose in cs.repo has rotated off (404), fall back to the
# latest available compose so builds don't fail on infra churn.
curl --retry 3 -Lo "/etc/yum.repos.d/compose.repo" "https://gitlab.com/redhat/centos-stream/containers/bootc/-/raw/c${MAJOR_VERSION_NUMBER}s/cs.repo"
sed -i \
	-e "s@- (BaseOS|AppStream)@& - Compose@" \
	-e "s@\(baseos\|appstream\)@&-compose@" \
	/etc/yum.repos.d/compose.repo

PINNED_COMPOSE=$(grep -oE "CentOS-Stream-[0-9]+-[0-9]+\.[0-9]+" /etc/yum.repos.d/compose.repo | head -1)
COMPOSE_BASE="https://composes.stream.centos.org/stream-${MAJOR_VERSION_NUMBER}/production"
if ! curl --retry 2 -sfI "${COMPOSE_BASE}/${PINNED_COMPOSE}/compose/BaseOS/x86_64/os/repodata/repomd.xml" > /dev/null 2>&1; then
    echo "Pinned compose ${PINNED_COMPOSE} is unavailable, finding latest..."
    LATEST_COMPOSE=$(curl --retry 3 -s "${COMPOSE_BASE}/" | grep -oE "CentOS-Stream-[0-9]+-[0-9]+\.[0-9]+" | sort -V | tail -1)
    echo "Using compose: ${LATEST_COMPOSE}"
    sed -i "s|${PINNED_COMPOSE}|${LATEST_COMPOSE}|g" /etc/yum.repos.d/compose.repo
fi
cat /etc/yum.repos.d/compose.repo
