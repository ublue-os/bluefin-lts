# CentOS vs Fedora — bluefin-lts Build Context

bluefin-lts is built on **CentOS Stream 10**, not Fedora. This has critical implications for agents and contributors.

## What does NOT exist on CentOS Stream 10

| Fedora Feature | CentOS Equivalent | Notes |
|---|---|---|
| COPR CLI | **Direct URL only** | `dnf copr enable` is blocked by CI guard. Use `dnf config-manager --add-repo <url>` instead |
| `dnf5 copr` subcommand | N/A | Not available on CentOS |
| Fedora akmods tags | `ghcr.io/ublue-os/akmods-*:centos-10` | Use `centos-10` tag, not `coreos-stable` |

## What to use instead

- **Third-party packages**: Use [EPEL](https://docs.fedoraproject.org/en-US/epel/) (`dnf install epel-release`) — the CentOS equivalent for extra packages
- **COPR repos**: You can still USE COPR repos via direct `.repo` URL — but you must use the **`epel-10` chroot name**, not `centos-stream-10` (see below)
- **Akmods**: Pull from `ghcr.io/ublue-os/akmods-*:centos-10` (not `coreos-stable`)
- **Package availability**: Always verify a package exists in CentOS Stream repos before adding it

## COPR chroot naming — critical

**`epel-10` and `centos-stream-10` are the same thing** from the OS perspective, but COPR projects choose which chroot name they build against. Most COPR projects targeting EL10 use **`epel-10`**, not `centos-stream-10`.

**Always check the COPR API** before hardcoding a chroot name:
```bash
curl -s "https://copr.fedorainfracloud.org/api_3/project/search?query=OWNER/PROJECT" | python3 -m json.tool | grep chroot_repos -A 10
```

**Correct URL pattern:**
```bash
# ✅ Use epel-${MAJOR_VERSION_NUMBER} for most COPR projects
dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/OWNER/PROJECT/repo/epel-${MAJOR_VERSION_NUMBER}/OWNER-PROJECT-epel-${MAJOR_VERSION_NUMBER}.repo"

# ⚠️  Some COPR projects DO use centos-stream-10 — verify first
dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/OWNER/PROJECT/repo/centos-stream-${MAJOR_VERSION_NUMBER}/OWNER-PROJECT-centos-stream-${MAJOR_VERSION_NUMBER}.repo"
```

**Real example** (issue #48, fixed 2026-06-04): `jreilly1821/c10s-gnome-50` only has `epel-10` chroots. Using `centos-stream-10` caused a 404 on every GDX build until the URL was corrected.

## Common mistakes to avoid

1. **DO NOT** copy `copr_install_isolated()` patterns from `bluefin` build scripts — `dnf copr enable` is blocked by CI guard
2. **DO NOT** use `dnf5 copr enable` — the subcommand is unavailable and blocked
3. **DO NOT** assume `centos-stream-10` is the right COPR chroot — verify with the API; most projects use `epel-10`
4. **DO NOT** use `coreos-stable` or Fedora-version akmods tags
5. **DO NOT** assume Fedora package names match CentOS package names exactly

## CI guard

A CI step in `pr-testsuite.yml` checks that `copr enable` does not appear in `build_scripts/`. If you see this CI failure, replace with a direct `dnf config-manager --add-repo` URL using the correct chroot name. LTS does not use bluefin's `build_files/` path.
