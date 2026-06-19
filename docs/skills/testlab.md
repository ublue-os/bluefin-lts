# Testlab

## Target

| Item | Value |
|---|---|
| Host | `ghost` (`192.168.1.102`) |
| VM | `titan-lts` |
| Access | NodePort `30220` |
| Base image | `ghcr.io/ublue-os/bluefin:lts-hwe` |

## PR test loop

```bash
# on ghost
sudo podman build -t localhost/bluefin-lts:pr-<N>-test /tmp/build-context/

sudo podman run --rm --privileged \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v ~/VMs/titans/image:/output \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type raw --rootfs xfs localhost/bluefin-lts:pr-<N>-test

bash ~/src/skills/ghost-testlab/scripts/titan-lts-setup.sh --wait
cd ~/src/skills/dakota-testlab && python3 lab-cli.py run --target lts
```

Use BIB disk rebuilds for test images; this is the supported path.

## Hard rules

- **Never use `bootc switch` inside the VM** for local unsigned images; `policy.json` requires signatures.
- Always rebuild the disk image, redeploy `titan-lts`, then run `lab-cli`.
- Post the report to the PR before merge.

## Report shape

### Header
```md
## ⚡ Vanguard Lab Strike Report: {hostname}
**Alpha**: Blue Universal CI Companion · Iron Lord Archive · Long Watch Protocol
**Guardian on Duty**: `castrojo` on Ghost Homelab

*"{flavor text}"*
```

### Required fields

| Field | Value |
|---|---|
| Target | `bluefin-lts` |
| VM/Host | `titan-lts` / NodePort `30220` |
| Image | `ghcr.io/ublue-os/bluefin:{tag}` + short digest |
| Verdict | `🟢 GO — ...` or `🔴 NOGO — ...` |
| Trailer | `<!-- status:{PASS|FAIL} target:lts label:{label} digest:{digest} -->` |

### Section order

1. System Identity
2. bootc Status
3. Desktop
4. Services
5. GNOME Extensions
6. Packages
7. Regression Canaries
8. Kernel
9. Custom Assertions

Canonical template: `skills/ghost-testlab/report-template.md` (Bluefin LTS example mapping).

## CI vs homelab

| Layer | Purpose |
|---|---|
| GitHub Actions smoke/e2e checks | verify workflow execution, image build/publish paths, and basic automation health |
| Ghost homelab (`titan-lts`) | last-mile validation for real booted desktop behavior, services, extensions, regressions, and manual canaries |

Treat homelab testing as complementary to CI, not a replacement. Merge only after both are satisfactory when the change is risky.