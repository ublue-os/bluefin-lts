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
| `generate-release.yml` | creates GitHub Release — only after e2e smoke passes |
| `pr-testsuite.yml` | runs `just check` + `just lint` on every PR; the only required check |
| `renovate-automerge.yml` | auto-merges Renovate PRs when pr-testsuite passes |

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

## Rechunker — chunkah v0.5.0

`reusable-build-image.yml` uses `coreos/chunkah` v0.5.0 (not `ublue-os/legacy-rechunk`).

**Implementation:** inline `buildah build` with the upstream `Containerfile.splitter`:
```bash
sudo buildah build --skip-unused-stages=false \
  --from "localhost/${IMAGE_NAME}:${DEFAULT_TAG}" \
  --build-arg "CHUNKAH=quay.io/coreos/chunkah:v0.5.0@sha256:352097f3d32186ac11082f8b74cd544678b00388b50c96ba5c8e79503a454fe3" \
  --build-arg "CHUNKAH_CONFIG_STR=$(sudo podman inspect ...)" \
  --build-arg "CHUNKAH_ARGS=--max-layers 128 --prune /sysroot/ --label ostree.commit- --label ostree.final-diffid-" \
  -t "localhost/${IMAGE_NAME}:${DEFAULT_TAG}" \
  -v "$(pwd):/run/src" \
  --security-opt=label=disable \
  https://github.com/coreos/chunkah/releases/download/v0.5.0/Containerfile.splitter
sudo rm -f out.ociarchive
# Transfer from root (buildah) storage to user (podman) storage
sudo podman save "${IMG}" | podman load
```

**Key flags for bootc images:**
- `--prune /sysroot/` — strips OSTree data not needed in OCI transport
- `--max-layers 128` — upstream recommendation for large bootc desktop images
- `--label ostree.commit- --label ostree.final-diffid-` — strips stale OSTree annotations
- `CHUNKAH_CONFIG_STR` — preserves `containers.bootc=1` and all other OCI labels
- `-v $(pwd):/run/src --security-opt=label=disable` — **required** for buildah < v1.44 (Ubuntu 24.04 ships 1.33.x) so the bind-mount persists `out.ociarchive` to the host CWD
- `sudo podman save ... | podman load` — **required**: `sudo buildah` writes to root container storage; unprivileged `podman` (used by Login/Push steps) uses a separate user store. The pipe transfers the rechunked image to user storage.

**Push:** all per-arch pushes use `--compression-format zstd:chunked --force-compression`.
zstd:chunked is complementary to chunkah: chunkah maximizes layer reuse (build-time);
zstd:chunked minimizes bytes fetched within changed layers (pull-time, HTTP range requests).

**`rechunk` input** (`bool`, default `true`): skip on PRs (`github.event_name != 'pull_request'`).
After rechunking, the image is retagged in-place; `Load Image` always picks up from `localhost/${IMAGE_NAME}:${DEFAULT_TAG}`.

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
| top-level `sign` job + manifest signing | `inputs.publish` |

If nothing is pushed, nothing should sign.

## Schedule ownership

`scheduled-lts-release.yml` is the **only** owner of Tuesday `0 6 * * 2` production runs. Do **not** add `schedule:` to the 5 build callers; scheduled caller runs on `main`, evaluates `publish=false`, and wastes runners.

## Renovate auto-merge pipeline (added 2026-05-30)

Renovate PRs are fully automated — no human needed:

1. Renovate opens PR → `pr-testsuite.yml` runs `just check` + `just lint` (~5 min)
2. `renovate-automerge.yml` triggers on `workflow_run` success → calls `gh pr merge --auto --merge`
3. Merge queue merges with `MERGE` commit (not squash)

**Required status check** (ruleset 4940669): `Lint & syntax` only.  
Builds run on PRs but are **informational** — they do not block merging.  
The weekly release e2e is the real quality gate for build correctness.

## Weekly release pipeline (updated 2026-05-30)

`scheduled-lts-release.yml` job chain:
1. `trigger-lts-builds` — triggers 5 builds on `lts`, waits for regular + dx + gdx to complete
2. `testsuite` — e2e smoke on `ghcr.io/projectbluefin/bluefin:lts` via `projectbluefin/testsuite/e2e.yml@main`
3. `generate-release` (needs: testsuite) — only fires if e2e passes; dispatches `generate-release.yml`

If e2e fails, no GitHub Release is created. Fix-forward, investigate, re-run manually.

## Release-generation pitfalls

- `workflow_run` chaining does not propagate from `GITHUB_TOKEN`-dispatched workflows reliably enough for LTS release generation.
- If touching `scheduled-lts-release.yml`, preserve the explicit wait/poll pattern before `generate-release.yml` so release creation happens after published tags exist.
- `pr-validate.yml` in `projectbluefin/testsuite` is NOT a reusable workflow (no `workflow_call`). Never call it with `uses:`; it is the testsuite's own linter.