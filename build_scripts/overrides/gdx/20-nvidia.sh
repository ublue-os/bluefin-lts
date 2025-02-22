#!/usr/bin/env bash

set -euox pipefail

dnf config-manager --add-repo="https://negativo17.org/repos/epel-nvidia.repo"
dnf config-manager --set-disabled "epel-nvidia"

dnf install -y --enablerepo="epel-nvidia" \
  akmod-nvidia kmod-nvidia cuda nvidia-driver{,-cuda}

sed -i -e 's/kernel$/kernel-open/g' /etc/nvidia/kernel.conf
cat /etc/nvidia/kernel.conf

# The nvidia-open driver tries to use the kernel from the host. (uname -r), just override it and let it do whatever otherwise
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"

cat >/tmp/fake-uname <<EOF
#!/usr/bin/env bash

if [ "\$1" == "-r" ] ; then
  echo ${QUALIFIED_KERNEL}
  exit 0
fi

exec /usr/bin/uname \$@
EOF
install -Dm0755 /tmp/fake-uname /tmp/bin/uname

# PATH modification for fake-uname
PATH=/tmp/bin:$PATH akmods --kernels "$QUALIFIED_KERNEL" --rebuild

cat >/usr/lib/modprobe.d/00-nouveau-blacklist.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

cat >/usr/lib/bootc/kargs.d/00-nvidia.toml <<EOF
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

# Make sure initramfs is rebuilt after nvidia drivers or kernel replacement
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v -f
