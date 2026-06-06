# CI/CD

## Workflow map

| File | Role |
|---|---|
| `build-regular.yml` | caller for `bluefin-lts` |
| `build-regular-hwe.yml` | caller for `bluefin-lts-hwe` (HWE kernel) |
| `build-gdx.yml` | caller for `bluefin-gdx` (NVIDIA/AI) |
| `scheduled-lts-release.yml` | only Tuesday production dispatcher; gated by `environment: production` (2-human approval); dispatches 3 build workflows on `lts` |
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
| ~~`create-lts-pr.yml`~~ | **deleted** — promotion is now via manually-reviewed PR gate (not auto-created) |

## Branches and tags

| Branch | Image | Tags | When |
|---|---|---|---|
| `main` | `bluefin-lts` | `testing`, `testing-YYYYMMDD` | every push/merge to `main` |
| `main` | `bluefin-lts-hwe` | `testing`, `testing-YYYYMMDD` | every push/merge to `main` |
| `main` | `bluefin-gdx` | `testing`, `testing-YYYYMMDD` | every push/merge to `main` |
| `lts` | `bluefin-lts` | `lts`, `lts-YYYYMMDD` | `workflow_dispatch` on `lts` only |
| `lts` | `bluefin-lts-hwe` | `lts`, `lts-YYYYMMDD` | `workflow_dispatch` on `lts` only |
| `lts` | `bluefin-gdx` | `lts`, `lts-YYYYMMDD` | `workflow_dispatch` on `lts` only |

`push` to `lts` does **not** trigger any build workflow (no `push: lts` trigger exists in any caller). The merge itself fires only `create-lts-pr.yml` and bonedigger.

## Promotion flow (`main→lts`)

1. Every push to `main` triggers `create-lts-pr.yml`, which opens/updates a draft PR `main→lts`.
2. A maintainer reviews and merges with a **regular merge commit** (not squash).
3. `scheduled-lts-release.yml` or manual dispatch on `lts` does the real publish.

**Never squash-merge promotion PRs.** It breaks the merge base and bloats every future PR diff.
**Never merge `lts→main`; never commit directly to `lts`.**

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

### Shared composite actions in bluefin-lts

| Action | Where used | LTS-specific override |
|---|---|---|
| `bootc-build/validate-pr` | `pr-testsuite.yml` | `shellcheck-glob: "build_scripts/**/*.sh"` (lts uses `build_scripts/`, not `build_files/`) |
| `bootc-build/detect-changes` | `build-regular.yml`, `build-gdx.yml`, `build-regular-hwe.yml` | filters for `build_scripts/**` and `image-versions.yaml` |
| `bootc-build/sign-and-publish` | called internally by `reusable-build.yml@v1` | `signing-mode: keyless` |

## Schedule ownership

`scheduled-lts-release.yml` is the **only** owner of Tuesday `0 6 * * 2` production runs. Do **not** add `schedule:` to the 3 build callers; scheduled caller runs would fire on `main`, produce `stream_name: testing`, and publish redundant testing tags.

## Renovate auto-merge pipeline

`renovate-automerge.yml` triggers on `workflow_run: completed: "PR Validation — testsuite"` and only proceeds when `conclusion == 'success'`. Both `renovate[bot]` and `app/mergeraptor` are accepted as PR authors.

When CI passes, the flow is:
1. Renovate (or `mergeraptor[bot]`) opens PR → `pr-testsuite.yml` runs lint + e2e smoke
2. `renovate-automerge.yml` triggers on `workflow_run` success → calls `gh pr merge --auto --merge`
3. Merge queue merges with `MERGE` commit (not squash)

**Required status check** (ruleset 4940669): `Lint & syntax` only.
Builds run on PRs but are **informational** — they do not block merging.

## Weekly release pipeline

`scheduled-lts-release.yml` job chain:
1. `trigger-lts-builds` — **gated by `environment: production` (2 required human approvals)**; dispatches 3 build workflows on `lts` branch, then waits for each to complete
2. `run-upgrade-test` — lifecycle upgrade test via `projectbluefin/actions/.github/workflows/upgrade-test.yml@v1`
3. `generate-release` (needs: [trigger-lts-builds, run-upgrade-test]) — only fires if upgrade-test passes; dispatches `generate-release.yml --ref main -f target=lts`

If the upgrade test fails, no GitHub Release is created. Fix-forward, investigate, re-run manually.

**Production gate:** two distinct maintainers must approve in the GitHub Environments UI before any Tuesday builds run.

## `generate-release.yml` trigger logic

Fires in two ways:
1. **`workflow_dispatch`** (from `scheduled-lts-release.yml`): normal production path.
2. **`workflow_run: Build Bluefin LTS GDX`** on `lts` with `event == 'workflow_dispatch'` and `conclusion == 'success'`: catches independently-dispatched GDX runs.

Do not rely on the `workflow_run` path for routine releases — always use `scheduled-lts-release.yml`.

## Release-generation pitfalls

- `workflow_run` chaining does not propagate from `GITHUB_TOKEN`-dispatched workflows reliably.
- Preserve the explicit wait/poll pattern in `scheduled-lts-release.yml` before `generate-release.yml` so release creation happens after published tags exist.
- `pr-validate.yml` in `projectbluefin/testsuite` is NOT a reusable workflow. Never call it with `uses:`.
| `bootc-build/create-manifest` | `reusable-build-image.yml` (manifest job) | default inputs |

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

`reusable-build-image.yml` calls `projectbluefin/actions/bootc-build/chunka@v1` with `force-compression: true`.

**Why `force-compression: true`:** LTS uses CentOS Stream 10, which must migrate existing registry layers from `gzip` to `zstd:chunked`. Fedora consumers (bluefin) leave this at the default `false` because their images are already `zstd:chunked`.

**What the action does internally** (reference only — do not duplicate inline):
- `buildah build` with upstream `Containerfile.splitter` at the pinned chunkah SHA
- Key flags: `--prune /sysroot/`, `--max-layers 128`, `--label ostree.commit-`, `--label ostree.final-diffid-`
- `-v $(pwd):/run/src --security-opt=label=disable` for buildah < v1.44 bind-mount stability
- `sudo podman save | podman load` to transfer rechunked image from root (buildah) to user (podman) storage

**Do not reproduce the inline buildah invocation.** All details live in `projectbluefin/actions/bootc-build/chunka/action.yml` and `docs/skills/composite-actions.md` → "chunka". If a flag needs changing, update the shared action, not `reusable-build-image.yml`.

**`rechunk` input** (`bool`, default `true`): skip on PRs (`github.event_name != 'pull_request'`). After rechunking, the image is retagged in-place; `Load Image` always picks up from `localhost/${IMAGE_NAME}:${DEFAULT_TAG}`.

## GHCR Package Access — PACKAGES_TOKEN

`ghcr.io/projectbluefin/bluefin` is linked to `projectbluefin/bluefin` (the main Bluefin repo),
not to `projectbluefin/bluefin-lts`. `GITHUB_TOKEN` from `bluefin-lts` is denied `write_package`.

**Workaround:** All `podman login`/`docker login`/`oras login` steps use:
```yaml
PUSH_TOKEN: ${{ secrets.PACKAGES_TOKEN || secrets.GITHUB_TOKEN }}
```

`PACKAGES_TOKEN` is a classic OAuth token (castrojo) with `write:packages` stored as a repo secret.

**To remove the workaround** (preferred long-term):
1. Go to https://github.com/orgs/projectbluefin/packages/container/bluefin/settings
2. Under "Manage Actions access" → "Add repository" → `projectbluefin/bluefin-lts` → Write
3. Repeat for `bluefin-dx` and `bluefin-gdx` packages
4. Delete the `PACKAGES_TOKEN` secret; revert login steps to `secrets.GITHUB_TOKEN`

## SBOM rules

- Generate/attest SBOMs **only** on `refs/heads/lts` **and** when `inputs.publish` is true.
- All SBOM steps must keep `continue-on-error: true`.
- Failed SBOM attestation must never block image publishing.
- LTS uses SPDX JSON artifacts on the amd64 manifest digest; signing uses keyless cosign (Sigstore OIDC).

## Condition quick reference

| Step/job | Condition |
|---|---|
| SBOM steps | `github.ref == 'refs/heads/lts' && inputs.publish` + `continue-on-error: true` |
| Rechunk (chunkah) | `inputs.rechunk && inputs.publish` |
| Load/Login/Push/Cosign/Outputs/Manifest push | `inputs.publish` |
| manifest signing (inline in manifest job) | `inputs.publish` |

If nothing is pushed, nothing should sign.

## Schedule ownership

`scheduled-lts-release.yml` is the **only** owner of Tuesday `0 6 * * 2` production runs. Do **not** add `schedule:` to the 5 build callers; scheduled caller runs on `main`, evaluates `publish=false`, and wastes runners.

## Renovate auto-merge pipeline

**Current status: broken due to issue #34.** `renovate-automerge.yml` triggers on `workflow_run: completed: "PR Validation — testsuite"` and only proceeds when `conclusion == 'success'`. Because the `testsuite` (E2E smoke) job always fails, the whole pr-testsuite workflow conclusion is `failure` — so auto-merge never fires. Renovate PRs require manual `gh pr merge --auto` until issue #34 is resolved.

When E2E is fixed, the flow will be:

1. Renovate (or `mergeraptor[bot]`) opens PR → `pr-testsuite.yml` runs `just check` + `just lint` + e2e smoke (~15 min)
2. `renovate-automerge.yml` triggers on `workflow_run` success → calls `gh pr merge --auto --merge`
3. Merge queue merges with `MERGE` commit (not squash)

**Required status check** (ruleset 4940669): `Lint & syntax` only.
Builds run on PRs but are **informational** — they do not block merging.
The weekly release e2e is the real quality gate for build correctness.

## Weekly release pipeline (updated 2026-06-04)

`scheduled-lts-release.yml` job chain:
1. `trigger-lts-builds` — **gated by `environment: production` (2 required human approvals)**; triggers all 5 build workflows on `lts`, then sequentially waits for regular, DX, and GDX to complete (HWE builds run in parallel but are not waited for)
2. `run-upgrade-test` — lifecycle upgrade test on `ghcr.io/projectbluefin/bluefin:lts` via `projectbluefin/actions/.github/workflows/upgrade-test.yml@v1`; `suites: lifecycle`, `chunked_enabled: false`
3. `generate-release` (needs: [trigger-lts-builds, run-upgrade-test]) — only fires if upgrade-test passes; dispatches `generate-release.yml --ref main -f target=lts`

If the upgrade test fails, no GitHub Release is created. Fix-forward, investigate, re-run manually.

The old `testsuite` job (calling `projectbluefin/testsuite/e2e.yml`) was removed in PR #46 — that workflow is no longer maintained.

**Production gate:** before Tuesday builds run, two distinct maintainers must approve the deployment in the GitHub Environments UI. The gate is on `trigger-lts-builds`, so all downstream jobs (upgrade-test, generate-release) only run after approval.

## `generate-release.yml` trigger logic

`generate-release.yml` fires in two ways:
1. **`workflow_dispatch`** (from `scheduled-lts-release.yml`): always creates a release; this is the normal production path.
2. **`workflow_run: Build Bluefin LTS GDX`** on `lts` branch with `event == 'workflow_dispatch'` and `conclusion == 'success'`: this catches the case where GDX is dispatched independently. A release is only created when the GDX workflow was itself triggered by `workflow_dispatch` (not by a push-to-lts validation build).

Do not rely on the `workflow_run` path for routine releases — always use `scheduled-lts-release.yml`.

## Release-generation pitfalls

- `workflow_run` chaining does not propagate from `GITHUB_TOKEN`-dispatched workflows reliably enough for LTS release generation.
- If touching `scheduled-lts-release.yml`, preserve the explicit wait/poll pattern before `generate-release.yml` so release creation happens after published tags exist.
- `pr-validate.yml` in `projectbluefin/testsuite` is NOT a reusable workflow (no `workflow_call`). Never call it with `uses:`; it is the testsuite's own linter.
