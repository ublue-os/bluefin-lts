# Release

## Production release flow

1. Promotion lands via PR from `main` to `lts`.
2. Merge must be a **regular merge commit**.
3. `push` to `lts` only validates; it does **not** publish.
4. `scheduled-lts-release.yml` owns the Tuesday `0 6 * * 2` production run.
5. **upgrade-test must pass** before GitHub Release is created.
6. For urgent publishes, manually dispatch `scheduled-lts-release.yml` on `lts`.

## Promotion / branch safety

- Never squash-merge promotion PRs.
- Never merge `lts→main`.
- Never commit directly to `lts`; land in `main` first.
- `main` uses a merge queue with **MERGE** method (not squash): `gh pr merge --auto` enqueues; do not promise immediate merge.
- Required check on `main` is `Lint & syntax` (pr-testsuite) only — builds are informational.

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
