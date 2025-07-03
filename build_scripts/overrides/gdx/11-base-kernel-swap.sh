# /*
#shellcheck disable=SC1083
# */

set ${CI:+-x} -euo pipefail

# /*
### Kernel Swap to Kernel signed with our MOK
# */

find /tmp/kernel-rpms

pushd /tmp/kernel-rpms
CACHED_VERSION=$(find $KERNEL_NAME-*.rpm | grep -P "$KERNEL_NAME-\d+\.\d+\.\d+-\d+$(rpm -E %{dist})" | sed -E "s/$KERNEL_NAME-//;s/\.rpm//")
popd

# /*
# always remove these packages as kernel cache provides signed versions of kernel or kernel-longterm
# */
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
  rpm --erase $pkg --nodeps || true
done
dnf -y install \
  /tmp/kernel-rpms/"$KERNEL_NAME"-"$CACHED_VERSION".rpm \
  /tmp/kernel-rpms/"$KERNEL_NAME"-core-"$CACHED_VERSION".rpm \
  /tmp/kernel-rpms/"$KERNEL_NAME"-modules-"$CACHED_VERSION".rpm \
  /tmp/kernel-rpms/"$KERNEL_NAME"-modules-core-"$CACHED_VERSION".rpm \
  /tmp/kernel-rpms/"$KERNEL_NAME"-modules-extra-"$CACHED_VERSION".rpm

# /*
### Version Lock kernel pacakges
# */
dnf versionlock add \
  "$KERNEL_NAME" \
  "$KERNEL_NAME"-core \
  "$KERNEL_NAME"-modules \
  "$KERNEL_NAME"-modules-core \
  "$KERNEL_NAME"-modules-extra
