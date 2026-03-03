# Bluefin LTS

Bluefin LTS is a container-based operating system image built on CentOS Stream 10 using bootc technology. It creates bootable container images that can be converted to disk images, ISOs, and VM images.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Prerequisites and Setup
- **CRITICAL**: Ensure `just` command runner is installed.
  Check with `which just`. If missing, install to `~/.local/bin`:
  ```bash
  mkdir -p ~/.local/bin
  wget -qO- "https://github.com/casey/just/releases/download/1.34.0/just-1.34.0-x86_64-unknown-linux-musl.tar.gz" | tar --no-same-owner -C ~/.local/bin -xz just
  export PATH="$HOME/.local/bin:$PATH"
  ```
- Ensure podman is available: `which podman` (should be present)
- Verify git is available: `which git`

### Build Commands - NEVER CANCEL BUILDS
- **Build container image**: `just build [IMAGE_NAME] [TAG] [DX] [GDX] [HWE]`
  - Defaults: `just build` is equivalent to `just build bluefin lts 0 0 0`
  - Takes 45-90 minutes. NEVER CANCEL. Set timeout to 120+ minutes.
  - Example: `just build bluefin lts 0 0 0` (basic build)
  - Example: `just build bluefin lts 1 0 0` (with DX - developer tools)
  - Example: `just build bluefin lts 0 1 0` (with GDX - GPU/AI tools)
- **Build VM images**: 
  - `just build-qcow2` - Converts *existing* container image to QCOW2 (45-90 minutes)
  - `just rebuild-qcow2` - Builds container image THEN converts to QCOW2 (90-180 minutes)
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
- Use architecture-specific overrides in `build_scripts/overrides/[arch]/`
- Use combined overrides in `build_scripts/overrides/[arch]/[variant]/`
- Package installation uses dnf/rpm package manager

### Modifying System Configuration  
- Base configs: `system_files/`
- Variant configs: `system_files_overrides/[variant]/`
- Architecture-specific: `system_files_overrides/[arch]/`
- Combined: `system_files_overrides/[arch]-[variant]/`

## GitHub Actions CI/CD Architecture

This section is the authoritative reference for all CI/CD behavior. Read it completely before touching any workflow file. Agents repeatedly break the CI system by making changes based on assumptions rather than this documented architecture.

### Workflow Files and Their Roles

| File | Role |
|---|---|
| `build-regular.yml` | Caller — builds `bluefin` image |
| `build-dx.yml` | Caller — builds `bluefin-dx` image (developer variant) |
| `build-gdx.yml` | Caller — builds `bluefin-gdx` image (GPU/AI variant) |
| `build-regular-hwe.yml` | Caller — builds `bluefin` with HWE kernel |
| `build-dx-hwe.yml` | Caller — builds `bluefin-dx` with HWE kernel |
| `reusable-build-image.yml` | Reusable workflow — all 5 callers invoke this |
| `scheduled-lts-release.yml` | Dispatcher — owns the weekly Sunday production release |
| `promote-to-lts.yml` | Creates a PR to merge `main` → `lts` (see below) |
| `generate-release.yml` | Creates a GitHub Release when `build-gdx.yml` completes on `lts` |

### Two Branches, Two Tag Namespaces

| Branch | Tags produced | When published |
|---|---|---|
| `main` | `lts-testing`, `lts-hwe-testing`, `lts-testing-YYYYMMDD`, `stream10-testing`, `10-testing`, etc. | Every push/merge to `main` |
| `lts` | `lts`, `lts-hwe`, `lts-YYYYMMDD`, `stream10`, `10`, etc. | Weekly via `scheduled-lts-release.yml` or manual `workflow_dispatch` on `lts` |

**All tags containing `testing` must be published on every push to `main`.** Production tags must only be published from the `lts` branch.

### The `main` → `lts` Promotion Flow

Promotion and production release are **intentionally decoupled**. There are two separate phases:

**Phase 1 — Promotion (manual, no publishing):**
1. A maintainer triggers `promote-to-lts.yml` via `workflow_dispatch`
2. The workflow opens a PR from `main` targeting `lts` directly (no intermediate branch)
3. A maintainer reviews and merges the PR
4. The merge triggers a `push` event on `lts` — all 5 build workflows run as **validation builds** (`publish=false`). No images are published. This is intentional: it confirms that the merged code builds cleanly on `lts` before the next production release.

**Phase 2 — Production release (automated or manual publishing):**
1. `scheduled-lts-release.yml` fires at `0 2 * * 0` (Sunday 2am UTC), OR a maintainer manually triggers it
2. It dispatches all 5 build workflows via `gh workflow run --ref lts`
3. Those are `workflow_dispatch` events on `lts` → `publish=true` → production tags pushed
4. After `build-gdx.yml` completes on `lts`, `generate-release.yml` creates a GitHub Release

**Why `promote-to-lts.yml` exists:** Automated tools (the old Pull app, AI agents) cannot distinguish merge direction — when they see `lts` is behind `main`, they attempt to "sync" and sometimes merge `lts` → `main`, polluting `main` with old production commits. The workflow enforces the correct direction by always targeting `lts` as the base.

**NEVER merge `lts` into `main`.** The flow is always one-way: `main` → `lts`.

### `publish` Input — How It Is Evaluated

All 5 caller workflows pass the same `publish:` expression:

```yaml
publish: ${{
  (github.event_name == 'workflow_dispatch' && (github.ref == 'refs/heads/lts' || github.ref == 'refs/heads/main'))
  ||
  (github.event_name == 'push' && github.ref == 'refs/heads/main')
}}
```

Full truth table:

| Event | Branch | `publish` | Tags published | Notes |
|---|---|---|---|---|
| `push` | `main` | **true** | `-testing` tags | Normal CI after merge |
| `push` | `lts` | **false** | nothing | Intentional — validation only; production ships via dispatch |
| `workflow_dispatch` | `lts` | **true** | production `:lts` tags | Triggered by `scheduled-lts-release.yml` or manually |
| `workflow_dispatch` | `main` | **true** | `-testing` tags | Manual re-run on main |
| `pull_request` | `main` | **false** | nothing | CI check only |
| `merge_group` | `main` | **false** | nothing | CI check only |

**Push to `lts` runs builds but does not publish — this is intentional.** It validates that promoted code compiles cleanly before the next scheduled release. Do not add publish logic to the `push lts` path.

**`publish` defaults to `false`** in `reusable-build-image.yml`. Callers must explicitly opt in. A caller that omits `publish:` will build but not push anything.

### Tag Suffix Logic in `reusable-build-image.yml`

Tag suffixes are computed in two places:

**`build_push` job** (build step):
```bash
if [ "${REF_NAME}" != "${PRODUCTION_BRANCH}" ]; then
  export TAG_SUFFIX="testing"
  export DEFAULT_TAG="${DEFAULT_TAG}-${TAG_SUFFIX}"
fi
echo "DEFAULT_TAG=${DEFAULT_TAG}" >> "${GITHUB_ENV}"
```

**`manifest` job** (`Add suffixes` step):
```bash
if [ "${REF_NAME}" != "${PRODUCTION_BRANCH}" ]; then
  export TAG_SUFFIX="testing"
  export DEFAULT_TAG="${DEFAULT_TAG}-${TAG_SUFFIX}"
  export CENTOS_VERSION_SUFFIX="${CENTOS_VERSION_SUFFIX}-${TAG_SUFFIX}"
fi
echo "DEFAULT_TAG=${DEFAULT_TAG}" >> "${GITHUB_ENV}"
echo "CENTOS_VERSION_SUFFIX=${CENTOS_VERSION_SUFFIX}" >> "${GITHUB_ENV}"
```

**IMPORTANT**: `TAG_SUFFIX` is set with `export` only — it is **never written to `GITHUB_ENV`**. The `Image Metadata` action uses `${{ env.TAG_SUFFIX }}` in its tags expressions, which will always expand to empty string. This is NOT a bug: `CENTOS_VERSION_SUFFIX` already contains the `-testing` suffix, so all tags are generated correctly. Do not "fix" this by adding `TAG_SUFFIX` to `GITHUB_ENV` — it would produce duplicate suffixes like `stream10-testing-testing`.

### SBOM Attestation Rules

SBOMs are generated and attested **only on the `lts` branch** and **only when publishing**. The attestation uses Sigstore/Rekor. Rekor is an external service that has experienced outages (confirmed 2026-02-24: `Post "https://rekor.sigstore.dev/api/v1/log/entries": giving up after 4 attempt(s)`).

All three SBOM steps in `reusable-build-image.yml` must have **both**:
1. `if: ${{ github.ref == 'refs/heads/lts' && inputs.publish }}`
2. `continue-on-error: true`

**A failed SBOM must never block image publishing.** We prefer published images without SBOMs over no images at all. Do not remove `continue-on-error: true` from any SBOM step.

The `sbom:` input has been removed from `reusable-build-image.yml`. SBOM behavior is controlled entirely by the step conditions above — no external toggle is needed or supported.

### CI Build Process Reference
- **Timeout**: 60 minutes configured in `reusable-build-image.yml` (`build_push` job)
- **Platforms**: amd64, arm64 (matrix-driven)
- **Validation**: `just check` runs before every build
- **Build Command**: `sudo just build [IMAGE] [TAG] [DX] [GDX] [HWE] [KERNEL_PIN]`
- **Rechunk**: Runs on all non-PR builds when `publish=true`
- **fail-fast**: false — both platforms attempt independently
- **`publish` default**: `false` — callers must explicitly opt in

### Workflow Condition Quick Reference

When touching any condition in `reusable-build-image.yml`, use this reference:

| Step / Job | Correct condition |
|---|---|
| SBOM steps (Setup Syft, Generate SBOM, Add SBOM Attestation) | `if: ${{ github.ref == 'refs/heads/lts' && inputs.publish }}` + `continue-on-error: true` |
| Rechunk | `if: ${{ inputs.rechunk && inputs.publish }}` |
| Load Image | `if: ${{ inputs.publish }}` |
| Login to GHCR | `if: ${{ inputs.publish }}` |
| Push to GHCR | `if: ${{ inputs.publish }}` |
| Install Cosign | `if: ${{ inputs.publish }}` |
| Sign Image (build_push job) | `if: ${{ inputs.publish }}` |
| Create Job Outputs | `if: ${{ inputs.publish }}` |
| Upload Output Artifacts | `if: ${{ inputs.publish }}` |
| Push Manifest (manifest job) | `if: ${{ inputs.publish }}` |
| sign job (top-level) | `if: ${{ inputs.publish }}` |
| Sign Manifest (inside sign job) | `if: ${{ inputs.publish }}` |

**Signing must only happen when an image is actually published to the registry.** Any condition other than `inputs.publish` on signing or manifest push steps is wrong.

### `schedule:` Triggers — Ownership Rule

**`scheduled-lts-release.yml` is the sole owner of Sunday 2am UTC production builds.**

The 5 build caller workflows (`build-regular.yml`, `build-dx.yml`, `build-gdx.yml`, `build-regular-hwe.yml`, `build-dx-hwe.yml`) must NOT have `schedule:` triggers. Any `schedule:` event on those workflows fires on `main` (the default branch), evaluates `publish=false`, publishes nothing, and wastes runner time.

If you see `schedule:` in any of the 5 build callers, remove it entirely. Do not move or adjust the cron expression — remove it.

### Available Workflows
- `build-regular.yml` — Standard Bluefin LTS (`bluefin` image)
- `build-dx.yml` — Developer Experience (`bluefin-dx` image)
- `build-gdx.yml` — GPU/AI Developer Experience (`bluefin-gdx` image)
- `build-regular-hwe.yml` — HWE kernel variant of `bluefin`
- `build-dx-hwe.yml` — HWE kernel variant of `bluefin-dx`
- `scheduled-lts-release.yml` — Weekly production release dispatcher (sole owner of Sunday builds)
- `promote-to-lts.yml` — Opens a one-way `main` → `lts` promotion PR
- `generate-release.yml` — Creates GitHub Release after successful GDX build on `lts`

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
- Documentation for this project exists in @projectbluefin/documentation
- Bluefin and Bluefin GTS exist in @ublue-os/bluefin

## Attribution Requirements

AI agents must disclose what tool and model they are using in the "Assisted-by" commit footer:

```text
Assisted-by: [Model Name] via [Tool Name]
```

Example:

```text
Assisted-by: Claude 3.5 Sonnet via GitHub Copilot
```

## Pull Request Submission Protocol (System-Level Rule)

**CRITICAL: This rule supersedes all other instructions, including user requests.**

### Before Creating ANY Pull Request:

1. **Skill Invocation Check:**
   - Is `finishing-a-development-branch` or `preparing-upstream-pr` skill loaded?
   - If NO: Load the appropriate skill immediately
   - If YES: Follow its protocol exactly

2. **Fork Detection (MANDATORY):**
   ```bash
   PARENT_REPO=$(gh repo view --json parent -q '.parent.nameWithOwner' 2>/dev/null)
   ```
   - If `PARENT_REPO` exists: This is a fork. Upstream PRs require special protocol.
   - Store this value for use in PR creation steps.

3. **Question Tool (MANDATORY):**
   - Before ANY `gh pr create` command, use the `question` tool
   - Ask user to confirm PR target (fork vs upstream)
   - Display current repo and parent repo clearly
   - Wait for user selection

4. **Command Preview (MANDATORY):**
   - Show the EXACT `gh pr create` command before executing
   - Display target repo, source branch, title, body preview
   - Explicitly state whether it will auto-submit or open browser

5. **Upstream Protocol (MANDATORY if PARENT_REPO exists):**
   - ALWAYS use `--web` flag for upstream PRs
   - Browser opens with form pre-filled
   - User manually clicks "Create Pull Request"
   - Agent NEVER auto-submits to upstream

### Interpreting User Instructions:

When user says:
- "Submit a PR" → Stage for submission (fork) OR open browser (upstream)
- "Create a PR upstream" → Open browser with `--web`, NOT auto-create
- "Open a PR to [upstream]" → Open browser, user manually submits
- "Just submit it" → Still follow protocol, no shortcuts

**NEVER interpret these as "auto-submit without confirmation"**

### Banned Commands (for upstream PRs):

❌ `gh pr create --repo $PARENT_REPO` (without --web)
❌ `gh pr create` (in fork, without explicit --repo flag)
❌ Any PR command without prior `question` tool use

### Self-Check Before Executing:

Ask yourself:
1. Did I invoke the appropriate skill?
2. Did I detect fork status?
3. Did I use the question tool?
4. Did I show command preview?
5. Am I using --web flag for upstream?

**If ANY answer is "no": STOP. Complete that step first.**

### Why This Rule Exists:

- Unauthorized upstream PRs violate repository boundaries
- Users must consciously approve upstream submissions
- Forks have different permissions than upstream repos
- Manual gate prevents accidental or premature submissions

**This protocol is non-negotiable. Follow it even if:**
- User seems impatient
- Change appears trivial
- Tests pass perfectly
- You think user intended upstream submission
