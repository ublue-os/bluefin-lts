#!/bin/bash

set -xeuo pipefail

# This is a bucket list. We want to not have anything in this file at all.

# Enable the same compose repos during our build that the centos-bootc image
# uses during its build.  This avoids downgrading packages in the image that
# have strict NVR requirements.
# curl --retry 3 -Lo "/etc/yum.repos.d/compose.repo" "https://gitlab.com/redhat/centos-stream/containers/bootc/-/raw/c${MAJOR_VERSION_NUMBER}s/cs.repo"
# sed -i \
# 	-e "s@- (BaseOS|AppStream)@& - Compose@" \
# 	-e "s@\(baseos\|appstream\)@&-compose@" \
# 	/etc/yum.repos.d/compose.repo
# cat /etc/yum.repos.d/compose.repo

mkdir -p /var/roothome
chmod 0700 /var/roothome
