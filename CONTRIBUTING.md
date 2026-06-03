# CONTRIBUTING

Thanks for helping out!

Check the [Contributing Guide](https://docs.projectbluefin.io/contributing) for general contribution information. The sections below cover LTS-specific rules.

This repository is for building the LTS images. Most configuration lives in [@projectbluefin/common](https://github.com/projectbluefin/common) — start there for most changes.

## LTS-specific notes

- **PRs target `main`** — unlike the Fedora-based bluefin repo, do not target a `testing` branch.
- LTS is built on CentOS Stream 10. Package availability differs from the Fedora-based images — check compatibility before adding packages.
- Breaking changes require extra caution: LTS users expect conservative, stable upgrades.

## Mandatory gates (run before every PR)

```bash
just check                # validate Justfile syntax
pre-commit run --all-files   # lint and format (install: pip install pre-commit)
```

Both must pass cleanly. CI will also enforce them.

## Architecture

See [the architecture diagram](https://docs.projectbluefin.io/contributing#understanding-bluefins-architecture) for how LTS fits into the broader build pipeline.

Full contributor guidelines including CODEOWNERS, PR review requirements, and the Renovate automation model are in [AGENTS.md](AGENTS.md).
