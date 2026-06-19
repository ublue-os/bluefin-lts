# Bluefin LTS — Agent Quick Reference

**Lazy-load skills — read only what the task needs.**

## Skill Index

| Task | Load |
|---|---|
| Local build, validation, packages | `docs/skills/build.md` |
| CI/CD workflows, publish logic, tag namespaces | `docs/skills/ci-cd.md` |
| Testing PRs on ghost homelab (titan-lts) | `docs/skills/testlab.md` |
| Release, rollback, registry, ISO status | `docs/skills/release.md` |

## Always-On Rules

- **NEVER cancel builds** — 45–90 min, set 120+ min timeout
- **NEVER squash-merge** promotion PRs (`main→lts`) — breaks merge base permanently
- **NEVER re-enable LTS ISO builds** — Anaconda is broken on CentOS Stream base
- **NEVER commit directly to `lts` branch** — land in `main` first
- **NEVER merge `lts→main`** — flow is one-way: `main→lts` only

## Quick Commands

```bash
just check && just lint     # validate before every commit
just build bluefin lts      # full build (120+ min timeout)
```

## Attribution

Every commit must include:
```text
Assisted-by: [Model Name] via [Tool Name]
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
