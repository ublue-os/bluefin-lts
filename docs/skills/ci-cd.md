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

`scheduled-lts-release.yml` dispatches manually or on a Tuesday `0 6 * * 2` schedule. Job chain:

1. `check-promotion-floor` — 7-day minimum; bypassed by `workflow_dispatch`
2. `resolve` — pulls `:testing` digests for all 3 variants; verifies all 3 share the same `org.opencontainers.image.revision` (CentOS bootc base SHA — see pitfalls below); locks current `main` SHA as `locked_main_sha` via the GitHub API
3. `verify-signatures` — cosign-verifies all 3 `:testing` digests; cert-identity-regexp must be `projectbluefin/(bluefin-lts|actions)/.github/workflows/` (signing happens inside `projectbluefin/actions` reusable workflow, not the caller)
4. `run-upgrade-test` — lifecycle test via `upgrade-test.yml@v1`; **non-blocking** (known false positive — testsuite hardcodes `ghcr.io/ublue-os/` prefix; tracked in testsuite#412 / issue #102)
5. `promote` (`if: always() && resolve.success && verify-signatures.success && run-upgrade-test in [success,failure]`) — skopeo-copies `:testing` → `:lts` by digest; SHA guard checks `locked_main_sha` vs current `main` (fails if main advanced during e2e — re-run)
6. `update-lts-branch` (`if: always() && promote.success`) — fast-forwards `lts` to `locked_main_sha`; no-ops if `sync-main-to-lts.yml` already created a merge commit containing the target
7. `generate-release` (`if: always() && update-lts-branch.success`) — dispatches `generate-release.yml --ref main -f target=lts`
8. `close-failure-issue` (`if: always() && promote.success`) — closes any open `ci: weekly LTS release failure` issue
9. `report-failure` (`if: always() && failure()`) — opens/updates failure issue

## Release pipeline pitfalls

**`org.opencontainers.image.revision` is the CentOS base SHA, not the LTS repo SHA.**
The label is inherited from `quay.io/centos-bootc/centos-bootc:c10s`. Never compare it to a `projectbluefin/bluefin-lts` commit SHA. The `resolve` job captures `locked_main_sha` from the GitHub API separately for the SHA guard and `update-lts-branch`.

**GitHub Actions transitive failure propagation.**
When a transitive ancestor fails (e.g. `run-upgrade-test`), GitHub skips all downstream jobs — even ones that only `needs:` a job that succeeded. Jobs after `promote` must use `if: always() && needs.X.result == 'success'`, not just `if: needs.X.result == 'success'`.

**`lts` branch is always "ahead" of `main`.**
`sync-main-to-lts.yml` creates a regular merge commit on `lts` for every push to `main`. The fast-forward PATCH will fail with `Update is not a fast forward`. The `update-lts-branch` step checks with the compare API and no-ops if `lts` already contains the target SHA.

**`continue-on-error: true` is not valid on `uses:` jobs.**
actionlint rejects it. Make a job non-blocking by using `if: always() && ...` conditions on the jobs that depend on it.

**SHA guard fires if `main` advances during the upgrade-test window (~10 min).**
Just re-dispatch `scheduled-lts-release.yml` once main is quiet.

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

## GHCR Package Access — always use `github.token`, never custom PATs

**Policy: Custom tokens (PATs, `PACKAGES_TOKEN`, etc.) are an antipattern in this project.**
When a workflow can't access a package, fix the package permissions — do not create a token.

All CI steps use only `github.token` (or `secrets.GITHUB_TOKEN`) for GHCR access.
If you see a `PACKAGES_TOKEN` or any other secret used for registry login, that is a bug.

### Required package configuration (org admin, one-time setup)

Three GHCR packages must be linked to `projectbluefin/bluefin-lts` and grant Actions write access:

| Package | Settings URL |
|---|---|
| `bluefin-lts` | https://github.com/orgs/projectbluefin/packages/container/bluefin-lts/settings |
| `bluefin-lts-hwe` | https://github.com/orgs/projectbluefin/packages/container/bluefin-lts-hwe/settings |
| `bluefin-gdx` | https://github.com/orgs/projectbluefin/packages/container/bluefin-gdx/settings |

On each settings page:
1. **Connected repository** → set to `projectbluefin/bluefin-lts`
2. **Manage Actions access** → "Add repository" → `projectbluefin/bluefin-lts` → **Write**

Once done, `github.token` from any `bluefin-lts` workflow has full package read/write — no PAT needed.

> **Note:** `bluefin-lts` is currently (incorrectly) linked to `projectbluefin/bluefin` and `bluefin-gdx`
> has no linked repo. Until an org admin fixes this, GHCR pushes from `bluefin-lts` workflows will fail
> with `DENIED`. The fix is the two-step UI action above — not a new secret.

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
