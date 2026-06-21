# Release

## Production release flow

1. Promotion lands via PR from `main` to `lts`.
2. Merge must be a **regular merge commit**.
3. `push` to `lts` only validates; it does **not** publish.
4. `scheduled-lts-release.yml` owns the Tuesday `0 6 * * 2` production run.
5. **e2e smoke test must pass** before GitHub Release is created.
6. For urgent publishes, manually dispatch `scheduled-lts-release.yml` on `lts`.

## Promotion / branch safety

- Never squash-merge promotion PRs.
- Never merge `lts→main`.
- Never commit directly to `lts`; land in `main` first.
- `main` uses a merge queue with **MERGE** method (not squash): `gh pr merge --auto` enqueues; do not promise immediate merge.
- Required check on `main` is `Lint & syntax` (pr-testsuite/PR Validation) only — builds are informational.

## Fork sync pattern (`castrojo` fork)

```bash
git fetch upstream
git rebase upstream/main
git push origin <branch> --force-with-lease

# after upstream merge
git checkout main
git reset --hard upstream/main
git push origin main --force-with-lease
```

Do not merge `upstream/main` into the fork; rebase instead.

## Registry queries

```bash
gh auth token | skopeo login ghcr.io -u castrojo --password-stdin
skopeo list-tags docker://ghcr.io/ublue-os/bluefin
```

Images publish to `ghcr.io/ublue-os/bluefin`.

## Emergency rollback

Use immutable dated tags as rollback sources.

| Image | Floating tags with dated rollback source |
|---|---|
| `bluefin` | `lts`, `lts-hwe`, `lts-amd64`, `lts-hwe-amd64` |
| `bluefin-dx` | `lts`, `lts-hwe`, `lts-amd64`, `lts-hwe-amd64` |
| `bluefin-gdx` | `lts`, `lts-amd64` |

```bash
GHCR_TOKEN=$(gh auth token)
skopeo copy \
  --src-no-creds \
  --dest-creds "castrojo:${GHCR_TOKEN}" \
  docker://ghcr.io/ublue-os/IMAGE:FLOATING_TAG.YYYYMMDD \
  docker://ghcr.io/ublue-os/IMAGE:FLOATING_TAG

skopeo inspect --no-creds docker://ghcr.io/ublue-os/IMAGE:FLOATING_TAG \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('Digest:', d['Digest']); print('Created:', d['Created'])"
```

Rollback every affected floating tag, then verify digest/created time for each.

## arm64 caveat

`lts-arm64`, `lts-hwe-arm64`, DX arm64, and GDX arm64 have **no dated snapshots**. There is no rollback path for those tags; recovery is **fix-forward only**.

## ISO status

**LTS ISO is disabled. Do not re-enable or promote it.**

- Do not enable `build-iso-lts.yml` schedules.
- Do not run `promote-iso.yml` with `variant: lts` or `variant: all`.
- Do not run `build-iso-all.yml` for LTS promotion.
- Existing production ISOs remain safe; new LTS ISO builds must stay blocked because Anaconda is broken on the CentOS Stream LTS base.