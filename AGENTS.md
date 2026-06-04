# Bluefin LTS — Agent & Copilot Instructions

**Bluefin LTS** is the long-term support variant of Bluefin, built on CentOS Stream with bootc.
Home repo: [projectbluefin/bluefin-lts](https://github.com/projectbluefin/bluefin-lts)

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

**When an agent opens a PR:** remove `queue/agent-ready` from the issue, add `queue/claimed` to both the issue and the PR. This signals the work is done and a human is next to review.

### PR comment policy

One comment per PR event, max. Combine all findings. Never post a follow-up — edit the existing comment.
Never duplicate GitHub UI state (approvals, CI status).
Test reports: what ran + pass/fail + blockers only. No diff summaries.
@ mentions only when asking someone to do something specific. Never standalone.
When in doubt, post nothing.

### Mandatory gates

- `just check && just lint` before every commit
- **Pre-commit guard:** `no-floating-action-tags` blocks third-party `@main`/`@v*` floating action tags at commit time. `projectbluefin/` refs (`@v1`, `@main`) are intentional managed tags and are exempted.
- PR title: Conventional Commits format
- Attribution on every AI-authored commit: `Assisted-by: <Model> via <Tool>`
- Max 4 open PRs at a time per agent
- No WIP PRs
- **Agents MUST NOT push directly to `main`.** All changes via PR. Branch protection enforces this.
- **Agents MUST NOT push directly to `lts`.** Land in `main` first; promotion to `lts` is handled automatically by GitHub Actions.
- **Production builds** (`scheduled-lts-release.yml`) require 2 distinct human approvals in the GitHub `production` Environment. No agent may trigger, approve, or bypass this gate. Admin bypasses are permanently logged in Environment deployment history.
- **bluefin-lts workflow path overrides are intentional:** use `build_scripts/` and `image-versions.yaml`, not bluefin's `build_files/` and `image-versions.yml`.
- **`.github/workflows/`, `Justfile`, and `build_scripts/` are CODEOWNERS-protected** — PRs touching these paths require maintainer review.

## Skills

Load only what the task needs:

| Task | Load |
|---|---|
| Local build, validation, packages | `docs/skills/build.md` |
| CI/CD workflows, publish logic, tag namespaces | `docs/skills/ci-cd.md` |
| CentOS-vs-Fedora package/repo decisions | `docs/skills/centos-vs-fedora.md` |
| Testing PRs on ghost homelab (titan-lts) | `docs/skills/testlab.md` |
| Release, rollback, registry, ISO status | `docs/skills/release.md` |

## Branch model

- `main` — active development (default). All PRs target `main`.
- `lts` — production releases only. Promotion is one-way: `main → lts`.

## Hard rules

- **NEVER cancel builds** — 45–90 min, set 120+ min timeout
- **NEVER squash-merge** promotion PRs (`main→lts`) — breaks merge base permanently
- **NEVER re-enable LTS ISO builds** — Anaconda is broken on CentOS Stream base
- **NEVER commit directly to `lts` branch** — land in `main` first
- **NEVER merge `lts→main`** — flow is one-way: `main→lts` only

## Quick commands

```bash
just check && just lint     # validate before every commit
just build bluefin lts      # full build (120+ min timeout)
```
