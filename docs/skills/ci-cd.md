# CI/CD

## Workflow map

| File | Role |
|---|---|
| `build-regular.yml` | caller for `bluefin-lts` |
| `build-regular-hwe.yml` | caller for `bluefin-lts-hwe` (HWE kernel) |
| `build-gdx.yml` | caller for `bluefin-gdx` (NVIDIA/AI) |
| `sync-main-to-lts.yml` | auto-merges `main → lts` on every push to `main`; thin caller to `projectbluefin/actions/reusable-sync-branches.yml@v1` |
| `scheduled-lts-release.yml` | Tuesday production dispatcher; dispatches 3 build workflows on `lts`; production environment gate **removed** (TODO #94 to restore once factory confirmed operational) |
| `generate-release.yml` | creates GitHub Release — only after e2e smoke passes |
| `pr-testsuite.yml` | runs **`validate-pr@v1`** (just check, shellcheck, hadolint, pre-commit) + **e2e smoke** on every PR; only `Lint & syntax` is a required check |
| `renovate-automerge.yml` | auto-merges Renovate/mergeraptor PRs when pr-testsuite passes |
| `post-merge-e2e.yml` | runs E2E smoke+common suites after a successful build on `main`; informational only |
| `skill-drift.yml` | warns on PRs that change CI/build/system files without updating docs/skills |
| `hive-progress-sync.yml` | posts queue stats + CI status to the projectbluefin org project board |
| `validate-renovate.yaml` | validates `.github/renovate.json5` on relevant PRs and pushes |
| `bonedigger.yml` | issue lifecycle automation (via `projectbluefin/common`) |
| ~~`build-dx.yml`~~ | **deleted** — no DX variant in LTS; GDX is the NVIDIA product |
| ~~`build-dx-hwe.yml`~~ | **deleted** — no DX HWE variant |
| ~~`build-gnome50.yml`~~ | **deleted 2026-05-30** — GNOME 50 is now the default |
| ~~`reusable-build-image.yml`~~ | **deleted** — replaced by `projectbluefin/actions/.github/workflows/reusable-build.yml@v1` |
| ~~`create-lts-pr.yml`~~ | **deleted 2026-05-30** (commit `82e2b67`) — replaced by `sync-main-to-lts.yml` (PR #97, merged 2026-06-06) |

## Branches and tags

| Branch | Image | Tags | When |
|---|---|---|---|
| `main` | `bluefin-lts` | `testing`, `testing-YYYYMMDD` | every push/merge to `main` |
| `main` | `bluefin-lts-hwe` | `testing`, `testing-YYYYMMDD` | every push/merge to `main` |
| `main` | `bluefin-gdx` | `testing`, `testing-YYYYMMDD` | every push/merge to `main` |
| `lts` | `bluefin-lts` | `lts`, `lts-YYYYMMDD` | `workflow_dispatch` on `lts` only |
| `lts` | `bluefin-lts-hwe` | `lts`, `lts-YYYYMMDD` | `workflow_dispatch` on `lts` only |
| `lts` | `bluefin-gdx` | `lts`, `lts-YYYYMMDD` | `workflow_dispatch` on `lts` only |

`push` to `lts` does **not** trigger any build workflow (no `push: lts` trigger exists in any caller). The merge itself fires only bonedigger and `hive-progress-sync.yml`.

## Promotion flow (`main→lts`)

`sync-main-to-lts.yml` auto-merges `main → lts` on every push to `main` via direct `git push` (uses `projectbluefin/actions/reusable-sync-branches.yml@v1`). No manual PR needed.

1. PRs merge to `main` via the merge queue using **squash merge**.
2. `sync-main-to-lts.yml` fires immediately after and merges `main → lts` via regular `git merge`.
3. `push` to `lts` does **not** publish images — it only validates.
4. `scheduled-lts-release.yml` (manual dispatch on `lts`) publishes production images.

**Never squash-merge `main→lts` directly.** The sync workflow uses regular merge — this is intentional to preserve merge base.
**Never merge `lts→main`.**

## `stream_name` — how tags are determined

The 3 callers delegate entirely to `projectbluefin/actions/.github/workflows/reusable-build.yml@v1`. The key input is `stream_name`:

```yaml
stream_name: ${{ github.ref == 'refs/heads/lts' && 'lts' || 'testing' }}
```

| `stream_name` | Tags published |
|---|---|
| `testing` | `testing`, `testing-YYYYMMDD` |
| `lts` | `lts`, `lts-YYYYMMDD` |

There is no separate `publish: false` gate. Callers always publish when they run. On PRs, the `detect-changes` job may skip the build entirely if no image-relevant files changed.

## Event truth table

| Event | Ref | Tags published | Notes |
|---|---|---|---|
| `push` | `main` | `testing`, `testing-YYYYMMDD` | normal CI after merge |
| `push` | `lts` | nothing | no build callers trigger on lts push |
| `workflow_dispatch` | `main` | `testing`, `testing-YYYYMMDD` | manual re-run |
| `workflow_dispatch` | `lts` | `lts`, `lts-YYYYMMDD` | triggered by `scheduled-lts-release.yml` or manually |
| `pull_request` | `main` | nothing | CI only; detect-changes may skip build entirely |
| `merge_group` | `main` | nothing | CI only |

## Centralized CI — `projectbluefin/actions`

Common CI/CD logic lives in reusable GitHub Actions at **https://github.com/projectbluefin/actions** (`@v1`).

### Reusable workflow used by bluefin-lts callers

`projectbluefin/actions/.github/workflows/reusable-build.yml@v1`

Inputs used by each caller:
- `brand_name` — image name (`bluefin-lts`, `bluefin-lts-hwe`, `bluefin-gdx`)
- `stream_name` — `testing` or `lts`
- `image_flavors` — `'["main"]'`
- `architecture` — `'["x86_64"]'`

### HWE and GDX kernel selection

HWE (`bluefin-lts-hwe`) and GDX (`bluefin-gdx`) use the **Fedora CoreOS stable** kernel, not the CentOS kernel. The Justfile resolves the current Fedora CoreOS stable version at build time:

```bash
skopeo inspect docker://quay.io/fedora/fedora-coreos:stable
# → derives Fedora version (e.g., 44) → selects coreos-stable-44 akmods
```

This means HWE/GDX kernels automatically track upstream as CoreOS advances Fedora versions — no manual pin bumps needed. Set `COREOS_STABLE_VERSION=NN` to override for testing.

Regular builds (`bluefin-lts`) use `centos-10` akmods and the CentOS Stream kernel.

### Shared composite actions in bluefin-lts| Action | Where used | LTS-specific override |
|---|---|---|
| `bootc-build/validate-pr` | `pr-testsuite.yml` | `shellcheck-glob: "build_scripts/**/*.sh"` (lts uses `build_scripts/`, not `build_files/`) |
| `bootc-build/detect-changes` | `build-regular.yml`, `build-gdx.yml`, `build-regular-hwe.yml` | filters for `build_scripts/**` and `image-versions.yaml` |
| `bootc-build/sign-and-publish` | called internally by `reusable-build.yml@v1` | `signing-mode: keyless` |

## Schedule ownership

`scheduled-lts-release.yml` is the **only** owner of Tuesday `0 6 * * 2` production runs. Do **not** add `schedule:` to the 3 build callers; scheduled caller runs would fire on `main`, produce `stream_name: testing`, and publish redundant testing tags.

## Renovate auto-merge pipeline

**Current status: broken due to issue #34.** `renovate-automerge.yml` triggers on `workflow_run: completed: "PR Validation — testsuite"` and only proceeds when `conclusion == 'success'`. Because the E2E smoke job always fails, the whole pr-testsuite workflow conclusion is `failure` — auto-merge never fires. Renovate PRs require manual `gh pr merge --auto` until issue #34 is resolved.

When E2E is fixed, the flow will be:
1. Renovate (or `mergeraptor[bot]`) opens PR → `pr-testsuite.yml` runs lint + e2e smoke
2. `renovate-automerge.yml` triggers on `workflow_run` success → calls `gh pr merge --auto --merge`
3. Merge queue merges with `MERGE` commit (not squash)

**Required status check** (ruleset 4940669): `Lint & syntax` only. Builds are informational.

## Weekly release pipeline

`scheduled-lts-release.yml` job chain (updated 2026-06-06):
1. `trigger-lts-builds` — ~~gated by `environment: production`~~ gate removed (TODO #94); triggers all 3 build workflows on `lts` (`build-regular.yml`, `build-gdx.yml`, `build-regular-hwe.yml`), then sequentially waits for all 3 to complete
2. `verify-signatures` (needs: trigger-lts-builds) — verifies cosign signatures on all 3 published images
3. `run-upgrade-test` (needs: [trigger-lts-builds, verify-signatures]) — lifecycle upgrade test on `ghcr.io/projectbluefin/bluefin-lts:lts` via `projectbluefin/actions/.github/workflows/upgrade-test.yml@v1`; `suites: lifecycle`, `chunked_enabled: false`
4. `generate-release` (needs: [trigger-lts-builds, run-upgrade-test]) — only fires if upgrade-test passes; dispatches `generate-release.yml --ref main -f target=lts`

If the upgrade test fails, no GitHub Release is created. Fix-forward, investigate, re-run manually.

**Branch protection on `main`:** Required check `Lint & syntax` + linear history enforced. Matches `projectbluefin/bluefin`.

## `generate-release.yml` trigger logic

Fires in two ways:
1. **`workflow_dispatch`** (from `scheduled-lts-release.yml`): always creates a release; this is the normal production path.
2. **`workflow_run: Build Bluefin LTS GDX`** on `lts` branch with `event == 'workflow_dispatch'` and `conclusion == 'success'`: catches independently-dispatched GDX runs.

Do not rely on the `workflow_run` path for routine releases — always use `scheduled-lts-release.yml`.

## Release-generation pitfalls

- `workflow_run` chaining does not propagate from `GITHUB_TOKEN`-dispatched workflows reliably enough for LTS release generation.
- If touching `scheduled-lts-release.yml`, preserve the explicit wait/poll pattern before `generate-release.yml` so release creation happens after published tags exist.
- `pr-validate.yml` in `projectbluefin/testsuite` is NOT a reusable workflow (no `workflow_call`). Never call it with `uses:`; it is the testsuite's own linter.

### bluefin vs bluefin-lts quick reference

These repo-local differences are the ones AI edits most often miss:

| Concern | bluefin default | bluefin-lts |
|---|---|---|
| Build shell path | `build_files/**/*.sh` | `build_scripts/**/*.sh` |
| Version file | `image-versions.yml` | `image-versions.yaml` |
| detect-changes filter | shared defaults often assume bluefin paths | always pass explicit `filters:` in `build-regular.yml` and `build-dx.yml` |
| PR shellcheck override | default action glob | `shellcheck-glob: "build_scripts/**/*.sh"` in `pr-testsuite.yml` |

If you copy workflow snippets from bluefin, translate those paths before saving.

### detect-changes filter override

bluefin-lts uses different paths from bluefin. **Always pass the `filters` input** when using detect-changes here:

```yaml
- uses: projectbluefin/actions/bootc-build/detect-changes@v1
  id: detect
  with:
    filters: |
      image:
        - 'Containerfile'
        - 'build_scripts/**'
        - 'system_files/**'
        - 'image-versions.yaml'
        - 'Justfile'
      nvidia:
        - 'Containerfile'
```

Using the default (bluefin paths: `build_files/**`, `image-versions.yml`) would silently skip builds when real image changes land.

### validate-pr glob override

Default `shellcheck-glob` watches `build_files/**/*.sh`. LTS must override:

```yaml
- uses: projectbluefin/actions/bootc-build/validate-pr@v1
  with:
    shellcheck-glob: "build_scripts/**/*.sh"
```

The same `build_scripts/` + `image-versions.yaml` distinction should stay consistent in `AGENTS.md`, `.github/CODEOWNERS`, and `skill-drift.yml`.

## Rechunker — chunka@v1 (projectbluefin/actions)

Rechunking is handled internally by `projectbluefin/actions/.github/workflows/reusable-build.yml@v1`. The local `reusable-build-image.yml` was deleted in PR #73.

**`force-compression: true`:** LTS uses CentOS Stream 10, which must migrate existing registry layers from `gzip` to `zstd:chunked`. Fedora consumers (bluefin) leave this at the default `false` because their images are already `zstd:chunked`.

**Rechunk is skipped for `stream_name == testing`** (on-push builds to `main`). Only production builds (`stream_name: lts`) rechunk.

**What the action does internally** (reference only — do not duplicate inline):
- `buildah build` with upstream `Containerfile.splitter` at the pinned chunkah SHA
- Key flags: `--prune /sysroot/`, `--max-layers 128`, `--label ostree.commit-`, `--label ostree.final-diffid-`
- `-v $(pwd):/run/src --security-opt=label=disable` for buildah < v1.44 bind-mount stability
- `sudo podman save | podman load` to transfer rechunked image from root (buildah) to user (podman) storage

**Do not reproduce the inline buildah invocation.** All details live in `projectbluefin/actions/bootc-build/chunka/action.yml`. If a flag needs changing, update the shared action.

## GHCR Package Access — PACKAGES_TOKEN

`ghcr.io/projectbluefin/bluefin` is linked to `projectbluefin/bluefin` (the main Bluefin repo),
not to `projectbluefin/bluefin-lts`. `GITHUB_TOKEN` from `bluefin-lts` is denied `write_package`.

**Workaround:** All `podman login`/`docker login`/`oras login` steps use:
```yaml
PUSH_TOKEN: ${{ secrets.PACKAGES_TOKEN || secrets.GITHUB_TOKEN }}
```

`PACKAGES_TOKEN` is a classic OAuth token (castrojo) with `write:packages` stored as a repo secret.

**To remove the workaround** (preferred long-term):
1. Go to https://github.com/orgs/projectbluefin/packages/container/bluefin-lts/settings
2. Under "Manage Actions access" → "Add repository" → `projectbluefin/bluefin-lts` → Write
3. Repeat for `bluefin-lts-hwe` and `bluefin-gdx` packages
4. Delete the `PACKAGES_TOKEN` secret; revert login steps to `secrets.GITHUB_TOKEN`

## SBOM rules

- Generate/attest SBOMs **only** on `refs/heads/lts` **and** when `inputs.publish` is true.
- All SBOM steps must keep `continue-on-error: true`.
- Failed SBOM attestation must never block image publishing.
- LTS uses SPDX JSON artifacts on the amd64 manifest digest; signing uses keyless cosign (Sigstore OIDC).

### SBOM permission gotcha (fixed 2026-06-06 — PR #90)

`reusable-build.yml` calls `sudo -E just gen-sbom` which creates `sbom_out/` **owned by root**.
The subsequent `sign-and-publish` step runs without `sudo` and fails with `permission denied` on `sbom_out/$IMAGE/sbom.json`.

**Fix is in the Justfile `gen-sbom` recipe:** after syft writes the file, ownership is returned to the invoking user:
```bash
chown -R "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "sbom_out/" 2>/dev/null || true
```

If you ever touch `gen-sbom` in the Justfile, preserve this line.

## Condition quick reference

| Step/job | Condition |
|---|---|
| SBOM steps | `github.ref == 'refs/heads/lts' && inputs.publish` + `continue-on-error: true` |
| Rechunk (chunkah) | `inputs.rechunk && inputs.publish` |
| Load/Login/Push/Cosign/Outputs/Manifest push | `inputs.publish` |
| manifest signing (inline in manifest job) | `inputs.publish` |

If nothing is pushed, nothing should sign.
