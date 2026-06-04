# Contributing to Bluefin LTS

Thanks for helping out.

Bluefin LTS is the long-term-support Bluefin variant built on a CentOS Stream base. Because it targets a longer support window, prefer conservative, low-risk changes and document behavior clearly.

General contributor guidance lives at [docs.projectbluefin.io/contributing](https://docs.projectbluefin.io/contributing).

## Pull requests

- Open PRs against the `main` branch
- Run `just check && just lint` before opening a PR
- PR CI on `main` runs lint/syntax validation; the E2E smoke test is informational only (see [issue #34](https://github.com/projectbluefin/bluefin-lts/issues/34))

## Prerequisites

- `just` — install with `brew install just` or your OS package manager
- `pre-commit` — install with `pip install pre-commit`, then run `pre-commit install`
- `podman` / `buildah` — required for local image builds

`just check` validates Justfile syntax and related script checks. `pre-commit run --all-files` runs linting and formatting hooks.

This repository builds the LTS images themselves. If your change belongs in the shared layer, you may be looking for [projectbluefin/common](https://github.com/projectbluefin/common) instead.
