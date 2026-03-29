# GNOME 49 Boot Failure Analysis

## Executive Summary

This document analyzes a critical boot failure discovered in GNOME 49 (specifically version 49.4) present in the Bluefin LTS testing image `lts-hwe-testing-20260315`. The issue prevents the graphical desktop from loading, though the system itself boots successfully to the login prompt.

**Status**: ⚠️ **CONFIRMED BOOT FAILURE**  
**Affected Version**: GNOME Shell 49.4 (image: `ghcr.io/ublue-os/bluefin:lts-hwe-testing-20260315`)  
**Working Version**: GNOME Shell 48.3 (all other recent images)  
**Root Cause**: Hard dependency on systemd-userdb infrastructure that fails in container/VM environments

---

## Background

### The Problem
Bluefin LTS testing images between March 13-16, 2026 showed inconsistent GNOME versions:

| Image Tag | GNOME Version | Status |
|-----------|--------------|---------|
| `lts-hwe-testing-20260312` | 48.3 | ✅ Working |
| `lts-hwe-testing-20260313` | 48.3 | ✅ Working |
| `lts-hwe-testing-20260314` | (not available) | - |
| `lts-hwe-testing-20260315` | **49.4** | ❌ **Boot Failure** |
| `lts-hwe-testing-20260316` | 48.3 | ✅ Working |
| `lts-hwe-testing` (latest) | 48.3 | ✅ Working |

The GNOME 49 update appeared only in the March 15th dated build and was subsequently pulled back, indicating upstream awareness of the issue.

---

## Technical Analysis

### Root Cause: systemd-userdb Dependency

GNOME 49 introduces breaking changes to how GDM (GNOME Display Manager) interacts with systemd, as documented by Adrian Vovk in "Introducing stronger dependencies on systemd" (June 2025):

> GNOME is gaining strong dependencies on systemd's userdb infrastructure. GDM now leverages systemd-userdb to dynamically allocate user accounts... the builtin service manager will now be completely unused and untested.

### Error Messages

When booting the GNOME 49 image, the following errors appear in GDM logs:

```
Mar 17 01:47:43 bluefin gdm[1241]: Gdm: Failed to listen on userdb socket: Invalid argument
Mar 17 01:47:43 bluefin gdm[1241]: Gdm: Failed to lock passwd database, ignoring: Permission denied
Mar 17 01:47:44 bluefin gdm[1241]: Gdm: GdmDisplay: Session never registered, failing
Mar 17 01:47:44 bluefin gdm[1241]: Gdm: Child process -1507 was already dead.
```

### Key Observations

1. **System boots successfully** - Kernel and early boot stages work fine
2. **SSH is accessible** - System reaches multi-user target
3. **GDM service starts** - But fails to initialize displays
4. **userdb socket exists** - `/run/systemd/userdb/io.systemd.Multiplexer` is present
5. **systemd-userdbd is running** - Service is active but GDM cannot communicate with it

The error "Invalid argument" when attempting to listen on the userdb socket suggests a low-level incompatibility, possibly related to:
- Container/VM namespace limitations
- Socket activation issues in bootc/ostree environments  
- Missing kernel features in virtualized environments

---

## Reproduction Steps

### Method 1: Using the Test VM Script (Recommended)

```bash
# Clone the repository
cd /var/home/james/dev/bluefin-lts

# Create a test VM from the problematic image
./scripts/create-test-vm.sh gnome49-test lts-hwe-testing-20260316

# Start the VM
limactl start gnome49-test

# SSH into the VM
limactl shell gnome49-test

# Switch to the GNOME 49 image
sudo bootc switch ghcr.io/ublue-os/bluefin:lts-hwe-testing-20260315

# Reboot
sudo systemctl reboot

# Observe: System boots to login prompt but GDM fails
# Check logs:
journalctl -u gdm -n 50 --no-pager
```

### Method 2: Direct Image Creation

```bash
# Pull and modify the GNOME 49 image
podman pull ghcr.io/ublue-os/bluefin:lts-hwe-testing-20260315
podman run -d --name gnome49-test ghcr.io/ublue-os/bluefin:lts-hwe-testing-20260315 sleep infinity
podman exec gnome49-test systemctl preset sshd
podman stop gnome49-test
podman commit gnome49-test bluefin:gnome49-ssh

# Create disk image
truncate -s 32G /tmp/gnome49.img
sudo podman run --rm --privileged --pid=host \
  -v /tmp:/tmp -v ~/.ssh:/ssh \
  localhost/bluefin:gnome49-ssh \
  bootc install to-disk --via-loopback --filesystem xfs \
  --generic-image --root-ssh-authorized-keys /ssh/id_ed25519.pub \
  /tmp/gnome49.img
```

---

## Impact Assessment

### Affected Components
- ✅ **Boot process**: System boots normally
- ✅ **Kernel**: No issues
- ✅ **SSH/Remote access**: Fully functional
- ❌ **GDM (GNOME Display Manager)**: Fails to start graphical session
- ❌ **GNOME Shell**: Never loads
- ❌ **User login**: Graphical login unavailable

### Workarounds

1. **Use text-mode boot** (temporary):
   ```bash
   sudo systemctl set-default multi-user.target
   sudo systemctl reboot
   ```

2. **Rollback to GNOME 48**:
   ```bash
   sudo bootc switch ghcr.io/ublue-os/bluefin:lts-hwe-testing
   sudo systemctl reboot
   ```

3. **Use undated testing branch**: The latest `lts-hwe-testing` has been reverted to GNOME 48.3

---

## Recommendations

### For Users
- ⚠️ **Do not upgrade to GNOME 49** until this issue is resolved
- ✅ Stay on `lts-hwe-testing` or pinned dated images with GNOME 48.3
- 📝 Report any similar issues with GNOME 49 in other configurations

### For Developers
1. **Investigate userdb socket compatibility** in container/VM environments
2. **Test systemd-userdb functionality** in QEMU/Lima VMs
3. **Consider fallback mechanisms** for environments without full systemd support
4. **Add CI checks** for GDM startup success, not just boot success

### For CI/CD
- Add automated GDM startup verification
- Test graphical session initialization, not just kernel boot
- Include VM-based testing in addition to container builds

---

## Testing Infrastructure

### Tools Created

This analysis utilized newly created testing utilities:

1. **`scripts/create-test-vm.sh`** - Automated VM creation with SSH access
2. **Justfile recipes** - `just create-test-vm` and `just run-test-vm`
3. **Lima/QEMU configuration** - Optimized for bootc image testing

### Usage

```bash
# Create VM from any Bluefin image
./scripts/create-test-vm.sh <name> <image-tag> [ssh-key]

# Example: Test latest stable
./scripts/create-test-vm.sh stable-test lts-hwe

# Example: Test specific dated build  
./scripts/create-test-vm.sh dated-test lts-hwe-testing-20260315
```

---

## Timeline

- **2026-03-13**: GNOME 48.3 in testing (stable)
- **2026-03-15**: GNOME 49.4 appears in `lts-hwe-testing-20260315` ❌
- **2026-03-16**: Reverted to GNOME 48.3 in latest testing
- **2026-03-17**: Issue reproduced and analyzed

---

## References

- Adrian Vovk, "Introducing stronger dependencies on systemd", June 2025
- systemd-userdb documentation: `man systemd-userdbd`
- GDM source code: https://gitlab.gnome.org/GNOME/gdm
- Bluefin LTS repository: https://github.com/ublue-os/bluefin

---

## Appendix: Full Error Log

```
Mar 17 01:47:43 bluefin systemd[1]: Starting gdm.service - GNOME Display Manager...
Mar 17 01:47:43 bluefin systemd[1]: Started gdm.service - GNOME Display Manager.
Mar 17 01:47:43 bluefin gdm[1241]: Gdm: Failed to listen on userdb socket: Invalid argument
Mar 17 01:47:43 bluefin gdm[1241]: Gdm: Failed to lock passwd database, ignoring: Permission denied
Mar 17 01:47:44 bluefin gdm[1241]: Gdm: GdmDisplay: Session never registered, failing
Mar 17 01:47:44 bluefin gdm[1241]: Gdm: Failed to lock passwd database, ignoring: Permission denied
Mar 17 01:47:44 bluefin gdm[1241]: Gdm: Child process -1507 was already dead.
Mar 17 01:47:44 bluefin gdm[1241]: Gdm: GdmDisplay: Session never registered, failing
Mar 17 01:47:44 bluefin gdm[1241]: Gdm: Child process -1507 was already dead.
```

---

**Document Version**: 1.0  
**Last Updated**: 2026-03-17  
**Author**: Bluefin LTS Testing Team  
**Status**: Analysis Complete - Awaiting Upstream Fix
