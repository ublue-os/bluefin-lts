#!/bin/bash

set -xeuo pipefail

# This is a bucket list. We want to not have anything in this file at all.

# Enable the same compose repos during our build that the centos-bootc image
# uses during its build.  This avoids downgrading packages in the image that
# have strict NVR requirements.
curl --retry 3 -Lo "/etc/yum.repos.d/compose.repo" "https://gitlab.com/redhat/centos-stream/containers/bootc/-/raw/c${MAJOR_VERSION_NUMBER}s/cs.repo"
sed -i -f - /etc/yum.repos.d/compose.repo <<EOF
s@- (BaseOS|AppStream)@& - Compose@
s@\(baseos\|appstream\)@&-compose@
EOF
