# CI/CD

## Workflow map

| File | Role |
|---|---|
| `build-regular.yml` | caller for `bluefin` |
| `build-dx.yml` | caller for `bluefin-dx` |
| `build-gdx.yml` | caller for `bluefin-gdx` |
| `build-regular-hwe.yml` | caller for HWE `bluefin` |
| `build-dx-hwe.yml` | caller for HWE `bluefin-dx` |
| `reusable-build-image.yml` | shared build/push/sign logic |
| `scheduled-lts-release.yml` | only Tuesday production dispatcher; gates GitHub Release on e2e |
| `create-lts-pr.yml` | opens/updates draft `main→lts` promotion PR |
| `generate-release.yml` | creates GitHub Release — only after e2e smoke passes |
| `pr-testsuite.yml` | runs `just check` + `just lint` on every PR; the only required check |

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

## SBOM rules

- Generate/attest SBOMs **only** on `refs/heads/lts` **and** when `inputs.publish` is true.
- All SBOM steps must keep `continue-on-error: true`.
- Failed SBOM attestation must never block image publishing.
- LTS uses SPDX JSON artifacts on the amd64 manifest digest; signing is key-based, not OIDC keyless.

## Condition quick reference

| Step/job | Condition |
|---|---|
| SBOM steps | `github.ref == 'refs/heads/lts' && inputs.publish` + `continue-on-error: true` |
| Rechunk | `inputs.rechunk && inputs.publish` |
| Load/Login/Push/Cosign/Outputs/Manifest push | `inputs.publish` |
| top-level `sign` job + manifest signing | `inputs.publish` |

If nothing is pushed, nothing should sign.

## Schedule ownership

`scheduled-lts-release.yml` is the **only** owner of Tuesday `0 6 * * 2` production runs. Do **not** add `schedule:` to the 5 build callers; scheduled caller runs on `main`, evaluates `publish=false`, and wastes runners.

## Renovate auto-merge pipeline

Renovate merges its own PRs through GitHub's native auto-merge. This repo has no workflow that merges Renovate PRs; `.github/renovate.json5` is the single policy.

1. Renovate opens a PR against `main` and enables auto-merge only when the matching `packageRules` entry allows it.
2. `pr-testsuite.yml` runs `just check` + `just lint` (~5 min).
3. GitHub's merge queue merges with `MERGE` commit (not squash) once the required check passes.

`platformAutomerge` is enabled at the top of `.github/renovate.json5`. Digest, pin, and GitHub Actions minor/patch updates auto-merge. Git submodule bumps (GNOME Shell extensions), wallpapers, and ChairLift bumps stay manual via later `automerge: false` rules; the submodule rule landed in #2267 after extension bumps merged with red builds.

**Required status check** (ruleset 4940669): `Lint & syntax` only.  
Builds run on PRs but are **informational** — they do not block merging.  
The weekly release e2e is the real quality gate for build correctness.

## Weekly release pipeline (updated 2026-06-21)

`scheduled-lts-release.yml` job chain:
1. `trigger-lts-builds` — triggers 5 builds on `lts`, waits for regular + dx to complete (GDX is not a gate)
2. `generate-release` (needs: trigger-lts-builds) — dispatches `generate-release.yml` on `main`

The `testsuite` job was removed 2026-06-21: calling `projectbluefin/testsuite/e2e.yml` via `uses:` was causing `startup_failure` on every run since 2026-06-02. Testsuite does not belong in this repo's release pipeline.

GDX is triggered by `trigger-lts-builds` but the release does **not wait** for it: GDX has a separate build stability track and its failures should not block regular+DX releases.

## Release-generation pitfalls

- `workflow_run` chaining does not propagate from `GITHUB_TOKEN`-dispatched workflows reliably enough for LTS release generation.
- If touching `scheduled-lts-release.yml`, preserve the explicit wait/poll pattern before `generate-release.yml` so release creation happens after published tags exist. The wait and retry logic lives in `scripts/lts-build-wait.sh` and is covered by `scripts/test-lts-build-wait.sh`.
- **Never merge a promotion PR to `lts` while a release run is in progress.** The push to `lts` cancels all in-flight build workflows dispatched by the release. The wait helper sees the `cancelled` conclusion and fails `trigger-lts-builds`, so no release is generated. Always wait for the release to reach `generate-release` before touching `lts`.

## GDX build notes

GDX (`build_scripts/overrides/gdx/20-nvidia.sh`) uses the **EPEL** negativo17 nvidia repo, not the Fedora one. Key facts:

- `ublue-os-nvidia-addons` (installed from akmods RPMs) ships `/etc/yum.repos.d/negativo17-epel-nvidia.repo` (disabled). Enable it per-command with `--enablerepo=epel-nvidia`.
- Do **not** fetch `negativo17/repos/fedora-nvidia.repo` — that is for Fedora builds, not CentOS Stream 10.
- Starting with the 610.x driver series, `libnvidia-ml` is no longer published as a standalone package in EPEL 10. It is merged into `nvidia-driver-libs`. Install `nvidia-driver-libs-${NVIDIA_PKG_VERSION}` instead.