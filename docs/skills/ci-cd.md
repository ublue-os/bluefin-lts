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
| `scheduled-lts-release.yml` | only Tuesday production dispatcher |
| `create-lts-pr.yml` | opens/updates draft `main→lts` promotion PR |
| `generate-release.yml` | creates GitHub Release after LTS publish |

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

## Release-generation pitfalls

- `workflow_run` chaining does not propagate from `GITHUB_TOKEN`-dispatched workflows reliably enough for LTS release generation.
- If touching `scheduled-lts-release.yml`, preserve the explicit wait/poll pattern before `generate-release.yml` so release creation happens after published tags exist.