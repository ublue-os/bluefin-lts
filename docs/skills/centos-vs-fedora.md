# CentOS vs Fedora — bluefin-lts Build Context

bluefin-lts is built on **CentOS Stream 10**, not Fedora. This has critical implications for agents and contributors.

## What does NOT exist on CentOS Stream 10

| Fedora Feature | CentOS Equivalent | Notes |
|---|---|---|
| COPR | **None** | COPR is Fedora-only. Never use `copr enable` or `copr_install_isolated()` in bluefin-lts |
| `dnf5 copr` subcommand | N/A | Not available on CentOS |
| Fedora akmods tags | `ghcr.io/ublue-os/akmods-*:centos-10` | Use `centos-10` tag, not `coreos-stable` |

## What to use instead

- **Third-party packages**: Use [EPEL](https://docs.fedoraproject.org/en-US/epel/) (`dnf install epel-release`) — the CentOS equivalent for extra packages
- **Akmods**: Pull from `ghcr.io/ublue-os/akmods-*:centos-10` (not `coreos-stable`)
- **Package availability**: Always verify a package exists in CentOS Stream repos before adding it

## Common mistakes to avoid

1. **DO NOT** copy `copr_install_isolated()` patterns from `bluefin` build scripts — COPR does not exist here
2. **DO NOT** use `dnf5 copr enable` — the subcommand is unavailable
3. **DO NOT** use `coreos-stable` or Fedora-version akmods tags
4. **DO NOT** assume Fedora package names match CentOS package names exactly

## CI guard

A CI step checks that `copr enable` does not appear in `build_scripts/`. If you see this CI failure, you are using a Fedora-only pattern that must be replaced. LTS does not use bluefin's `build_files/` path.
