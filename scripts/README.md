# Bluefin LTS Utility Scripts

## create-test-vm.sh

Creates a test VM from a Bluefin LTS bootc image with SSH enabled, suitable for testing in Lima/QEMU.

### Usage

```bash
./scripts/create-test-vm.sh [VM_NAME] [IMAGE_TAG] [SSH_PUB_KEY]
```

**Arguments:**
- `VM_NAME` (optional, default: `bluefin-test-ssh`): Name for the VM
- `IMAGE_TAG` (optional, default: `lts-hwe`): Bluefin image tag to use
- `SSH_PUB_KEY` (optional, default: `$HOME/.ssh/id_ed25519.pub`): SSH public key to inject

### Example

```bash
# Create a test VM with default settings
./scripts/create-test-vm.sh

# Create a VM named "gnome49-test" using lts-hwe-testing image
./scripts/create-test-vm.sh gnome49-test lts-hwe-testing

# Create with specific SSH key
./scripts/test-vm.sh my-test lts-hwe ~/.ssh/mykey.pub
```

### What It Does

1. Pulls the specified Bluefin LTS image
2. Runs the container and enables SSH daemon using `systemctl preset sshd`
3. Commits the modified container to a new local image
4. Creates a 32GB disk image using `bootc install to-disk`
5. Injects the SSH public key for root login
6. Creates a Lima configuration file
7. Provides instructions for starting/managing the VM

### Output

The script creates:
- A modified container image: `bluefin-lts-ssh-test:TIMESTAMP`
- A disk image: `/tmp/bluefin-vm-<VM_NAME>.img`
- A Lima config: `~/.lima/<VM_NAME>/lima.yaml`

### Managing the VM

```bash
# Start the VM
limactl start <VM_NAME>

# Connect via SSH
limactl shell <VM_NAME>

# Stop the VM
limactl stop <VM_NAME>

# Delete the VM
limactl delete <VM_NAME>
```

### Requirements

- `podman` - for container operations
- `bootc` - for disk image creation
- `limactl` - for VM management
- `qemu` - for running VMs (used by lima)
- Sudo privileges - for bootc install operations
- SSH key pair - for authentication

### Notes

- The script enables SSH by presetting the sshd service in the container
- SSH keys are injected during the bootc install process
- Default disk size is 32GB, memory is 8GB, and 4 CPUs
- The VM uses VNC for display output
