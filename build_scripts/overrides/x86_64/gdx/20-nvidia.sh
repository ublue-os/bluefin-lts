#!/usr/bin/env bash

set -euox pipefail

# FIXME: add renovate rules for this (somehow?)
NVIDIA_DISTRO="rhel9"

# These are necessary for building the nvidia drivers
# DKMS is provided by EPEL
# Also make sure the kernel is locked before this is run whenever the kernel updates
# kernel-devel might pull in an entire new kernel if you dont do
dnf -y install kernel-devel kernel-devel-matched kernel-headers dkms gcc-c++

dnf config-manager --add-repo "https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_DISTRO}/$(arch)/cuda-${NVIDIA_DISTRO}.repo"
dnf clean expire-cache
NVIDIA_DRIVER_DIRECTORY=$(mktemp -d)
NVIDIA_DRIVER_FLAVOR=nvidia-open

# EGL-gbm and EGL-wayland fail to install because of conflicts with each other
dnf download egl-gbm egl-wayland --destdir="$NVIDIA_DRIVER_DIRECTORY"
rpm -ivh "$NVIDIA_DRIVER_DIRECTORY"/*.rpm --nodeps --force

dnf -y install --nogpgcheck \
	-x egl-wayland \
	-x egl-gbm \
	nvidia-driver{,-cuda} "kmod-$NVIDIA_DRIVER_FLAVOR-dkms"

KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"

# The nvidia-open driver tries to use the kernel from the host. (uname -r), just override it and let it do whatever otherwise
cat >/tmp/fake-uname <<EOF
#!/usr/bin/env bash

if [ "\$1" == "-r" ] ; then
  echo ${QUALIFIED_KERNEL}
  exit 0
fi

exec /usr/bin/uname \$@
EOF
install -Dm0755 /tmp/fake-uname /tmp/bin/uname

NVIDIA_DRIVER_VERSION=$(rpm -q "nvidia-driver" --queryformat '%{VERSION}')
# PATH modification for fake-uname
PATH=/tmp/bin:$PATH dkms --force install -m "$NVIDIA_DRIVER_FLAVOR" -v "$NVIDIA_DRIVER_VERSION" -k "$QUALIFIED_KERNEL"
cat "/var/lib/dkms/nvidia-open/$NVIDIA_DRIVER_VERSION/build/make.log" || echo "Expected failure"

cat >/usr/lib/modprobe.d/00-nouveau-blacklist.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

cat >/usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
match-architectures = ["x86_64"]
EOF

dnf -y remove kernel-devel kernel-devel-matched kernel-headers dkms gcc-c++

# Make sure initramfs is rebuilt after nvidia drivers or kernel replacement
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v -f
