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

# Step 2: Run container and enable SSH
echo "Step 2: Enabling SSH in container..."
CONTAINER_NAME="bluefin-ssh-temp-$$"
podman run -d --name "$CONTAINER_NAME" "ghcr.io/ublue-os/bluefin:$IMAGE_TAG" sleep infinity
sleep 3

# Enable SSH preset
podman exec "$CONTAINER_NAME" systemctl preset sshd

# Verify SSH is enabled
if podman exec "$CONTAINER_NAME" systemctl is-enabled sshd > /dev/null 2>&1; then
    echo "✓ SSH enabled successfully"
else
    echo "✗ Failed to enable SSH"
    podman rm -f "$CONTAINER_NAME"
    exit 1
fi

# Step 3: Commit the modified container
echo "Step 3: Creating modified image..."
IMAGE_NAME="bluefin-lts-ssh-test:$(date +%Y%m%d-%H%M%S)"
podman stop "$CONTAINER_NAME"
podman commit "$CONTAINER_NAME" "$IMAGE_NAME"
podman rm "$CONTAINER_NAME"

# Step 4: Create disk image
echo "Step 4: Creating disk image..."
DISK_IMAGE="/tmp/bluefin-vm-${VM_NAME}.img"
rm -f "$DISK_IMAGE"
truncate -s "$DISK_SIZE" "$DISK_IMAGE"

# Install to disk with SSH key
echo "Step 5: Installing to disk with SSH key injection..."
sudo podman run --rm --privileged --pid=host \
    -v /tmp:/tmp \
    -v "$(dirname "$SSH_PUB_KEY"):/ssh" \
    "$IMAGE_NAME" \
    bootc install to-disk \
    --via-loopback \
    --filesystem xfs \
    --generic-image \
    --root-ssh-authorized-keys "/ssh/$(basename "$SSH_PUB_KEY")" \
    "$DISK_IMAGE"

# Step 6: Create Lima configuration
echo "Step 6: Creating Lima configuration..."
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
