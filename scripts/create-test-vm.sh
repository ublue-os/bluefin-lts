#!/bin/bash
set -e

# Script to create a test VM from Bluefin LTS with SSH enabled
# This allows testing bootc images in Lima/QEMU VMs

VM_NAME="${1:-bluefin-test-ssh}"
IMAGE_TAG="${2:-lts-hwe}"
SSH_PUB_KEY="${3:-$HOME/.ssh/id_ed25519.pub}"
DISK_SIZE="32G"
MEMORY="8GiB"
CPUS="4"

echo "=== Bluefin LTS Test VM Creator ==="
echo "VM Name: $VM_NAME"
echo "Base Image: ghcr.io/ublue-os/bluefin:$IMAGE_TAG"
echo "SSH Key: $SSH_PUB_KEY"
echo ""

# Step 1: Pull the base image
echo "Step 1: Pulling base image..."
podman pull "ghcr.io/ublue-os/bluefin:$IMAGE_TAG"

# Step 2: Create disk image
echo "Step 2: Creating disk image..."
DISK_IMAGE="/tmp/bluefin-vm-${VM_NAME}.img"
rm -f "$DISK_IMAGE"
truncate -s "$DISK_SIZE" "$DISK_IMAGE"

# Install to disk with SSH key
echo "Step 3: Installing to disk with SSH key injection..."
sudo podman run --rm --privileged --pid=host -e BOOTC_SETENFORCE0_FALLBACK=1 \
    -v /tmp:/tmp \
    -v "$(dirname "$SSH_PUB_KEY"):/ssh" \
    "ghcr.io/ublue-os/bluefin:$IMAGE_TAG" \
    bootc install to-disk \
    --via-loopback \
    --filesystem xfs \
    --generic-image \
    --root-ssh-authorized-keys "/ssh/$(basename "$SSH_PUB_KEY")" \
    "$DISK_IMAGE"

# Step 4: Create Lima configuration with provision script
echo "Step 4: Creating Lima configuration..."
LIMA_DIR="$HOME/.lima/$VM_NAME"
mkdir -p "$LIMA_DIR"

cat > "$LIMA_DIR/lima.yaml" << EOF
cpus: $CPUS
images:
  - arch: x86_64
    location: $DISK_IMAGE
memory: $MEMORY
ssh:
  loadDotSSHPubKeys: true
  localPort: 2223
video:
  display: vnc
mountType: "9p"
mounts:
  - location: "~"
    writable: true
provision:
  - mode: system
    script: |
      #!/bin/bash
      # Enable SSH daemon persistently
      systemctl preset sshd
      systemctl enable sshd
      systemctl start sshd
      echo "SSH enabled successfully"
EOF

echo ""
echo "=== VM Creation Complete ==="
echo "VM Name: $VM_NAME"
echo "Disk Image: $DISK_IMAGE"
echo "Lima Config: $LIMA_DIR/lima.yaml"
echo ""
echo "To start the VM:"
echo "  limactl start $VM_NAME"
echo ""
echo "To connect via SSH:"
echo "  limactl shell $VM_NAME"
echo ""
echo "To stop the VM:"
echo "  limactl stop $VM_NAME"
echo ""
echo "To delete the VM:"
echo "  limactl delete $VM_NAME"
