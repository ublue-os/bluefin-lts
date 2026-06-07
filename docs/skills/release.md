# Release

## Production release flow

1. `sync-main-to-lts.yml` auto-promotes `main → lts` on every push via regular merge — no manual PR needed.
2. `push` to `lts` validates only; it does **not** publish images.
3. Dispatch manually to publish:
   ```bash
   gh workflow run scheduled-lts-release.yml --repo projectbluefin/bluefin-lts
   ```
4. `promote` skopeo-copies `:testing` → `:lts` by digest after cosign verify passes. The upgrade-test is **non-blocking** (known false positive on `ghcr.io/ublue-os/` prefix; tracked in testsuite#412 / issue #102).
5. `generate-release` fires after `update-lts-branch` succeeds.

## Promotion / branch safety

- `main→lts` is automated via `sync-main-to-lts.yml` (regular merge, direct git push).
- Never squash-merge `main→lts` directly — the sync workflow does regular merge intentionally.
- Never merge `lts→main`.
- `main` uses a merge queue with **squash** method. Required check: `Lint & syntax`. Linear history enforced.
- `gh pr merge --auto` enqueues — do not promise immediate merge.

## Fork sync pattern (`castrojo` fork)

```bash
git fetch projectbluefin
git rebase projectbluefin/main
git push origin <branch> --force-with-lease

# after merge to projectbluefin
git checkout main
git reset --hard projectbluefin/main
git push origin main --force-with-lease
```

Do not merge `projectbluefin/main` into the fork; rebase instead.

## Registry queries

```bash
gh auth token | skopeo login ghcr.io -u castrojo --password-stdin
skopeo list-tags docker://ghcr.io/projectbluefin/bluefin-lts
skopeo list-tags docker://ghcr.io/projectbluefin/bluefin-lts-hwe
skopeo list-tags docker://ghcr.io/projectbluefin/bluefin-gdx
```

Images publish to:
- `ghcr.io/projectbluefin/bluefin-lts` (base)
- `ghcr.io/projectbluefin/bluefin-lts-hwe` (HWE kernel)
- `ghcr.io/projectbluefin/bluefin-gdx` (NVIDIA/AI)

## Emergency rollback

Use immutable dated tags as rollback sources.

| Image | Floating tag | Rollback source |
|---|---|---|
| `bluefin-lts` | `lts` | `lts-YYYYMMDD` |
| `bluefin-lts-hwe` | `lts` | `lts-YYYYMMDD` |
| `bluefin-gdx` | `lts` | `lts-YYYYMMDD` |

```bash
GHCR_TOKEN=$(gh auth token)
skopeo copy \
  --src-no-creds \
  --dest-creds "castrojo:${GHCR_TOKEN}" \
  docker://ghcr.io/projectbluefin/IMAGE:lts-YYYYMMDD \
  docker://ghcr.io/projectbluefin/IMAGE:lts

skopeo inspect --no-creds docker://ghcr.io/projectbluefin/IMAGE:lts \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('Digest:', d['Digest']); print('Created:', d['Created'])"
```

Rollback every affected floating tag, then verify digest/created time for each.

## ISO status

**LTS ISO is disabled. Do not re-enable or promote it.**

- Do not enable `build-iso-lts.yml` schedules.
- Do not run `promote-iso.yml` with `variant: lts` or `variant: all`.
- Do not run `build-iso-all.yml` for LTS promotion.
- Existing production ISOs remain safe; new LTS ISO builds must stay blocked because Anaconda is broken on the CentOS Stream LTS base.
