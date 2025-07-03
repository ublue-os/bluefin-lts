# /*
#shellcheck disable=SC1083
# */

set -euo pipefail

# /*
### Kernel Swap to Kernel signed with our MOK
# */

find /tmp/kernel-rpms

pushd /tmp/kernel-rpms
CACHED_VERSION=$(find kernel-*.rpm | grep -P "kernel-\d+\.\d+\.\d+-\d+$(rpm -E %{dist})" | sed -E "s/kernel-//;s/\.rpm//")
popd

# /*
# always remove these packages as kernel cache provides signed versions of kernel or kernel-longterm
# */
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
  rpm --erase $pkg --nodeps || true
done
dnf -y install \
  /tmp/kernel-rpms/kernel-"$CACHED_VERSION".rpm \
  /tmp/kernel-rpms/kernel-core-"$CACHED_VERSION".rpm \
  /tmp/kernel-rpms/kernel-modules-"$CACHED_VERSION".rpm \
  /tmp/kernel-rpms/kernel-modules-core-"$CACHED_VERSION".rpm \
  /tmp/kernel-rpms/kernel-modules-extra-"$CACHED_VERSION".rpm

# /*
### Version Lock kernel pacakges
# */
dnf versionlock add \
  kernel \
  kernel-core \
  kernel-modules \
  kernel-modules-core \
  kernel-modules-extra
