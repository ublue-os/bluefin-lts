# Bluefin LTS

Bluefin LTS is a container-based operating system image built on CentOS Stream 10 using bootc technology. It creates bootable container images that can be converted to disk images, ISOs, and VM images.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Prerequisites and Setup
- **CRITICAL**: Install just command runner first:
  ```bash
  wget -qO- "https://github.com/casey/just/releases/download/1.34.0/just-1.34.0-x86_64-unknown-linux-musl.tar.gz" | tar --no-same-owner -C /usr/local/bin -xz just
  ```
- Ensure podman is available: `which podman` (should be present)
- Verify git is available: `which git`

### Build Commands - NEVER CANCEL BUILDS
- **Build container image**: `just build [IMAGE_NAME] [TAG] [DX] [GDX] [HWE]`
  - Takes 45-90 minutes. NEVER CANCEL. Set timeout to 120+ minutes.
  - Example: `just build bluefin lts 0 0 0` (basic build)
  - Example: `just build bluefin lts 1 0 0` (with DX - developer tools)
  - Example: `just build bluefin lts 0 1 0` (with GDX - GPU/AI tools)
- **Build VM images**: 
  - `just build-qcow2` - QCOW2 virtual machine image (45-90 minutes)
  - `just build-iso` - ISO installer image (45-90 minutes) 
  - `just build-raw` - RAW disk image (45-90 minutes)
  - NEVER CANCEL any build command. Set timeout to 120+ minutes.

### Validation and Testing
- **ALWAYS run syntax checks before making changes**:
  - `just check` - validates Just syntax (takes <30 seconds)
  - `just lint` - runs shellcheck on all shell scripts (takes <10 seconds)
  - `just format` - formats shell scripts with shfmt (takes <10 seconds)
- **Build validation workflow**:
  1. Always run `just check` before committing changes
  2. Always run `just lint` before committing changes  
  3. Test build with `just build bluefin lts` (120+ minute timeout)
  4. Test VM creation with `just build-qcow2` if modifying VM-related code

### Running Virtual Machines
- **Run VM from built images**:
  - `just run-vm-qcow2` - starts QCOW2 VM with web console on http://localhost:8006
  - `just run-vm-iso` - starts ISO installer VM
  - `just spawn-vm` - uses systemd-vmspawn for VM management
- **NEVER run VMs in CI environments** - they require KVM/graphics support

## Build System Architecture

### Key Build Variants
- **Regular**: Basic Bluefin LTS (`just build bluefin lts 0 0 0`)
- **DX**: Developer Experience with VSCode, Docker, development tools (`just build bluefin lts 1 0 0`)
- **GDX**: GPU Developer Experience with CUDA, AI tools (`just build bluefin lts 0 1 0`)  
- **HWE**: Hardware Enablement for newer hardware (`just build bluefin lts 0 0 1`)

### Core Build Process
1. **Container Build**: Uses Containerfile with CentOS Stream 10 base
2. **Build Scripts**: Located in `build_scripts/` directory
3. **System Overrides**: Architecture and variant-specific files in `system_files_overrides/`
4. **Bootc Conversion**: Container images converted to bootable formats via Bootc Image Builder

### Build Timing Expectations
- **Container builds**: 45-90 minutes (timeout: 120+ minutes)
- **VM image builds**: 45-90 minutes (timeout: 120+ minutes)
- **Syntax checks**: <30 seconds
- **Linting**: <10 seconds
- **Git operations**: <5 seconds

## Repository Structure

### Key Directories
- `build_scripts/` - Build automation and package installation scripts
- `system_files/` - Base system configuration files
- `system_files_overrides/` - Variant-specific overrides (dx, gdx, arch-specific)
- `.github/workflows/` - CI/CD automation (60-minute timeout configured)
- `Justfile` - Primary build automation (13KB+ file with all commands)

### Important Files
- `Containerfile` - Main container build definition
- `image.toml` - VM image build configuration  
- `iso.toml` - ISO build configuration
- `Justfile` - Build command definitions (use `just --list` to see all)

## Common Development Tasks

### Making Changes to Build Scripts
1. Edit files in `build_scripts/` for package changes
2. Edit `system_files_overrides/[variant]/` for variant-specific changes
3. Always run `just lint` before committing
4. Test with full build: `just build bluefin lts` (120+ minute timeout)

### Adding New Packages
- Edit `build_scripts/20-packages.sh` for base packages
- Use variant-specific overrides in `build_scripts/overrides/[variant]/`
- Package installation uses dnf/rpm package manager

### Modifying System Configuration  
- Base configs: `system_files/`
- Variant configs: `system_files_overrides/[variant]/`
- Architecture-specific: `system_files_overrides/[arch]/`

## GitHub Actions Integration

### CI Build Process
- **Timeout**: 60 minutes configured in reusable-build-image.yml
- **Platforms**: amd64, arm64 
- **Validation**: Runs `just check` before building
- **Build Command**: `sudo just build [IMAGE] [TAG] [DX] [GDX] [HWE]`

### Available Workflows
- `build-regular.yml` - Standard Bluefin LTS build
- `build-dx.yml` - Developer Experience variant
- `build-gdx.yml` - GPU Developer Experience variant
- `build-iso.yml` - ISO installer builds

## Validation Scenarios

### After Making Changes
1. **Syntax validation**: `just check && just lint`
2. **Build test**: `just build bluefin lts` (full 120+ minute build)
3. **VM test**: `just build-qcow2` (if modifying VM components)
4. **Manual testing**: Run VM and verify basic OS functionality

### Code Quality Requirements
- All shell scripts must pass shellcheck (`just lint`)
- Just syntax must be valid (`just check`)
- CI builds must complete within 60 minutes
- Always test the specific variant you're modifying (dx, gdx, regular)

## Common Commands Reference

```bash
# Essential validation (run before every commit)
just check                    # <30 seconds
just lint                     # <10 seconds

# Core builds (NEVER CANCEL - 120+ minute timeout)
just build bluefin lts        # Standard build
just build bluefin lts 1 0 0  # With DX (developer tools)
just build bluefin lts 0 1 0  # With GDX (GPU/AI tools)

# VM images (NEVER CANCEL - 120+ minute timeout)  
just build-qcow2              # QCOW2 VM image
just build-iso                # ISO installer
just build-raw                # Raw disk image

# Development utilities
just --list                   # Show all available commands
just clean                    # Clean build artifacts
git status                    # Check repository state
```

## Critical Reminders

- **NEVER CANCEL builds or long-running commands** - they may take 45-90 minutes
- **ALWAYS set 120+ minute timeouts** for build commands
- **ALWAYS run `just check && just lint`** before committing changes
- **This is an OS image project**, not a traditional application
- **Internet access may be limited** in some build environments
- **VM functionality requires KVM/graphics support** - not available in all CI environments

## Build Failures and Debugging

### Common Issues
- **Network timeouts**: Build pulls packages from CentOS repositories
- **Disk space**: Container builds require significant space (clean with `just clean`)
- **Permission errors**: Some commands require sudo/root access
- **Missing dependencies**: Ensure just, podman, git are installed

### Recovery Steps
1. Clean build artifacts: `just clean`
2. Verify tools: `which just podman git`
3. Check syntax: `just check && just lint`
4. Retry with full timeout: `just build bluefin lts` (120+ minutes)

Never attempt to fix builds by canceling and restarting - let them complete or fail naturally.

## Other Rules that are Important to the Maintainers

- Ensure that [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/#specification) are used and enforced for every commit and pull request title.
- Always be surgical with the least amount of code, the project strives to be easy to maintain.
- Documentation for this project exists in ublue-os/bluefin-docs
- Bluefin and Bluefin GTS exist in ublue-os/bluefin

## Attribution Requirements

AI agents must disclose what tool and model they are using in the "Assisted-by" commit footer:

```text
Assisted-by: [Model Name] via [Tool Name]
```

Example:

```text
Assisted-by: Claude 3.5 Sonnet via GitHub Copilot
```
