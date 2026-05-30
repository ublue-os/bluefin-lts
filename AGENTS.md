# AGENTS.md — projectbluefin/bluefin-lts

This file is for AI agents (Copilot, Claude, etc.) working in this repository.

## What this repo does

`bluefin-lts` is a Long-Term Support variant of Bluefin, built on CentOS Stream with bootc.
It consumes `ghcr.io/projectbluefin/common:latest` and produces CentOS-based images
that track a slower release cadence suitable for enterprise/production use.

**Branch model:**
- `main` — development, default branch, PRs target here
- `lts` — production, one-way promotion from main, never commit directly

## Skills

| Task | Load |
|---|---|
| Build + variant matrix | `bluefin-build` |
| CI failures | `bluefin-ci` |
| Package changes | `bluefin-packages` |
| Release process | `bluefin-release` |
| LTS-specific rules | `bluefin-lts` |

## Org pipeline — projectbluefin

### Repo map

```
common ──────────────────────────┐
(shared OCI layer)               │
                                 ▼
bluefin  (main→stable)       ←── images ──→ testsuite (e2e gate)
bluefin-lts (main→lts)       ←── images ──→ testsuite (e2e gate)
dakota  (main→:latest)       ←── images ──→ testsuite (e2e gate)
                                 │
                                 ▼
                                iso (installation media)
```

Each image repo pulls `ghcr.io/projectbluefin/common:latest` as a base layer.
testsuite gates `:latest` promotion in all three image repos.

### Issue lifecycle

`filed → approved → queued → claimed → done`

| Stage | How |
|---|---|
| `filed` | Issue opened |
| `approved` | Maintainer adds `status/approved` or comments `/approve` |
| `queued` | `queue/agent-ready` auto-added alongside approval |
| `claimed` | Comment `/claim` — assigned, removed from pool |
| `done` | Fix shipped + 3× `ujust verify` or maintainer override |

No PR activity in 7 days returns a claimed issue to the queue automatically.

### PR comment policy

One comment per PR event, max. Combine all findings. Never post a follow-up — edit the existing comment.
Never duplicate GitHub UI state (approvals, CI status).
Test reports: what ran + pass/fail + blockers only. No diff summaries.
@ mentions only when asking someone to do something specific. Never standalone.
When in doubt, post nothing.

### Mandatory gates

- `just check && pre-commit run --all-files` before every commit
- PR title: Conventional Commits format (`feat:`, `fix:`, `chore(deps):`, etc.)
- Attribution on every AI-authored commit: `Assisted-by: <Model> via <Tool>`
- Max 4 open PRs at a time per agent
- No WIP PRs

## Working on this repo

**Before opening a PR:**
1. All PRs target `main`
2. Never push directly to `lts`
3. Production promotion: main → lts happens via automated scheduled release
4. Run `just check` before committing

**Key files:**
- `.github/workflows/` — build + release workflows
- `docs/` — variant and upgrade documentation

## Related repos

- Upstream base: [projectbluefin/common](https://github.com/projectbluefin/common)
- Bluefin (Fedora variant): [projectbluefin/bluefin](https://github.com/projectbluefin/bluefin)
- E2E tests: [projectbluefin/testsuite](https://github.com/projectbluefin/testsuite)
- Install media: [projectbluefin/iso](https://github.com/projectbluefin/iso)
