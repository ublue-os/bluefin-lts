# CI/CD

## Workflow map

| File | Role |
|---|---|
| `build-regular.yml` | caller for `bluefin` |
| `build-dx.yml` | caller for `bluefin-dx` |
| `build-gdx.yml` | caller for `bluefin-gdx` |
| `build-regular-hwe.yml` | caller for HWE `bluefin` |
| `build-dx-hwe.yml` | caller for HWE `bluefin-dx` |
| `reusable-build-image.yml` | shared build/push/sign logic — calls `projectbluefin/actions@v1` composite actions |
| `scheduled-lts-release.yml` | only Tuesday production dispatcher; gates GitHub Release on `upgrade-test.yml@v1`; gated by `environment: production` (2-human approval) |
| `generate-release.yml` | creates GitHub Release — only after e2e smoke passes |
| `pr-testsuite.yml` | runs **`validate-pr@v1`** (just check, shellcheck, hadolint, pre-commit) + **e2e smoke** on every PR; only `Lint & syntax` is a required check |
| `renovate-automerge.yml` | auto-merges Renovate PRs when pr-testsuite passes |
| `skill-drift.yml` | warns on PRs that change CI/build files without updating docs/skills |
| ~~`build-gnome50.yml`~~ | **deleted 2026-05-30** — GNOME 50 is now the default; `lts-testing-50` tags are no longer produced |

## Branches and tags

| Branch | Publishes | When |
|---|---|---|
| `main` | `lts-testing`, `lts-hwe-testing`, `lts-testing-YYYYMMDD`, `stream10-testing`, `10-testing` | every push/merge |
| `lts` | `lts`, `lts-hwe`, `lts-YYYYMMDD`, `stream10`, `10` | `workflow_dispatch` only |

`push` to `lts` is validation only; no publish.

## Promotion flow (`main→lts`)

1. Push to `main` triggers `create-lts-pr.yml`.
2. Workflow compares content with `git diff --quiet origin/lts origin/main`.
3. If changed, it opens/updates a draft PR from `main` to `lts`.
4. Maintainer must use **Create a merge commit**.
5. Merge to `lts` triggers validation builds with `publish=false`.
6. `scheduled-lts-release.yml` or manual dispatch on `lts` does the real publish.

**Never squash-merge promotion PRs.** It breaks the merge base and bloats every future PR. Never merge `lts→main`; never commit directly to `lts`.

## `publish` truth table

| Event | Ref | `publish` | Result |
|---|---|---|---|
| `push` | `main` | true | publish testing tags |
| `push` | `lts` | false | build only |
| `workflow_dispatch` | `main` | true | publish testing tags |
| `workflow_dispatch` | `lts` | true | publish production tags |
| `pull_request` | `main` | false | CI only |
| `merge_group` | `main` | false | CI only |

`publish` defaults to `false` in `reusable-build-image.yml`; callers must opt in.

## Tag suffix logic

| Place | Behavior |
|---|---|
| `build_push` | non-production refs append `-testing` to `DEFAULT_TAG` |
| `manifest` job | non-production refs append `-testing` to `DEFAULT_TAG` and `CENTOS_VERSION_SUFFIX` |

`TAG_SUFFIX` is intentionally **not** written to `GITHUB_ENV`. Do not "fix" that; `CENTOS_VERSION_SUFFIX` already carries the suffix and adding both would create `*-testing-testing`.

## Centralized CI — `projectbluefin/actions`

Common CI/CD logic lives in reusable GitHub Actions at **https://github.com/projectbluefin/actions** (`@v1`).

### Actions adopted by bluefin-lts

| Action | Where used | LTS-specific override |
|---|---|---|
| `bootc-build/validate-pr` | `pr-testsuite.yml` | `shellcheck-glob: "build_scripts/**/*.sh"` (lts uses `build_scripts/`, not `build_files/`) |
| `bootc-build/detect-changes` | `build-dx.yml`, `build-regular.yml` | `filters:` input with `build_scripts/**` and `image-versions.yaml` |
| `bootc-build/chunka` | `reusable-build-image.yml` | `force-compression: true` (CentOS Stream requires gzip→zstd migration) |
| `bootc-build/setup-runner` | `reusable-build-image.yml` | default inputs |
| `bootc-build/dnf-cache` | `reusable-build-image.yml` | default inputs |
| `bootc-build/push-image` | `reusable-build-image.yml` | default inputs |
| `bootc-build/sign-and-publish` | `reusable-build-image.yml` (build_push job + manifest job) | `signing-mode: keyless` |
| `bootc-build/create-manifest` | `reusable-build-image.yml` (manifest job) | default inputs |

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

## Renovate auto-merge pipeline (added 2026-05-30)

Renovate PRs are fully automated — no human needed:

1. Renovate opens PR → `pr-testsuite.yml` runs `just check` + `just lint` + e2e smoke (~15 min)
2. `renovate-automerge.yml` triggers on `workflow_run` success → calls `gh pr merge --auto --merge`
3. Merge queue merges with `MERGE` commit (not squash)

**Required status check** (ruleset 4940669): `Lint & syntax` only.
Builds run on PRs but are **informational** — they do not block merging.
The weekly release e2e is the real quality gate for build correctness.

## Weekly release pipeline (updated 2026-06-04)

`scheduled-lts-release.yml` job chain:
1. `trigger-lts-builds` — **gated by `environment: production` (2 required human approvals)**; triggers 5 builds on `lts`, waits for regular + dx + gdx to complete
2. `run-upgrade-test` — lifecycle upgrade test on `ghcr.io/projectbluefin/bluefin:lts` via `projectbluefin/actions/.github/workflows/upgrade-test.yml@v1`; `suites: lifecycle`, `chunked_enabled: false`
3. `generate-release` (needs: [trigger-lts-builds, run-upgrade-test]) — only fires if upgrade-test passes; dispatches `generate-release.yml`

If the upgrade test fails, no GitHub Release is created. Fix-forward, investigate, re-run manually.

The old `testsuite` job (calling `projectbluefin/testsuite/e2e.yml`) was removed in PR #46 — that workflow is no longer maintained.

**Production gate:** before Tuesday builds run, two distinct maintainers must approve the deployment in the GitHub Environments UI. The gate is on `trigger-lts-builds`, so all downstream jobs (testsuite, generate-release) only run after approval. See `projectbluefin/actions/docs/skills/factory-operations.md` → "Production Gate" for configuration details.

## Release-generation pitfalls

- `workflow_run` chaining does not propagate from `GITHUB_TOKEN`-dispatched workflows reliably enough for LTS release generation.
- If touching `scheduled-lts-release.yml`, preserve the explicit wait/poll pattern before `generate-release.yml` so release creation happens after published tags exist.
- `pr-validate.yml` in `projectbluefin/testsuite` is NOT a reusable workflow (no `workflow_call`). Never call it with `uses:`; it is the testsuite's own linter.
