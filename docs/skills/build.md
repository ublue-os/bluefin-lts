# Build

## Prereqs

| Tool | Check | Install / note |
|---|---|---|
| `just` | `which just` | If missing: `mkdir -p ~/.local/bin && wget -qO- "https://github.com/casey/just/releases/download/1.34.0/just-1.34.0-x86_64-unknown-linux-musl.tar.gz" \| tar --no-same-owner -C ~/.local/bin -xz just && export PATH="$HOME/.local/bin:$PATH"` |
| `podman` | `which podman` | required for image + VM builds |
| `git` | `which git` | required |

## Fast validation

```bash
just check && just lint
```

- Run before every commit.
- `just check` validates Just syntax (<30s).
- `just lint` runs shellcheck (<10s).
- `just format` exists for shfmt when editing shell.

## Core builds

| Goal | Command | Typical time |
|---|---|---|
| Regular | `just build bluefin lts 0 0 0` | 45-90 min |
| DX | `just build bluefin lts 1 0 0` | 45-90 min |
| GDX | `just build bluefin lts 0 1 0` | 45-90 min |
| HWE | `just build bluefin lts 0 0 1` | 45-90 min |

The `gnome_version` parameter defaults to `"50"`. Override only if testing a future GNOME version. For GDX builds, `fedora_akmods_version` (default `"43"`) controls the negativo17 Fedora repo version used for NVIDIA drivers:

```bash
just build bluefin lts 0 1 0 "" 50 43   # GDX with explicit GNOME 50, Fedora 43 akmods
```

**Never cancel builds.** Use 120+ minute timeouts.

## Variant map

| Variant | What changes |
|---|---|
| Regular | base LTS image |
| DX | developer tools, VS Code, Docker |
| GDX | GPU / AI tooling |
| HWE | newer hardware enablement |

## VM / disk artifacts

| Command | Purpose | Time |
|---|---|---|
| `just build-qcow2` | convert existing container image to QCOW2 | 45-90 min |
| `just rebuild-qcow2` | build image, then QCOW2 | 90-180 min |
| `just build-raw` | raw disk image | 45-90 min |
| `just build-iso` | installer image; **LTS ISO remains disabled for release/promote work** | 45-90 min |
| `just run-vm-qcow2` | boot QCOW2; web console on `http://localhost:8006` | runtime |
| `just run-vm-iso` / `just spawn-vm` | local VM helpers | runtime |

Never run VMs in CI; KVM/graphics are required.

## Repo layout for build work

| Path | Use |
|---|---|
| `build_scripts/` | package install + build logic |
| `system_files/` | base system config |
| `system_files_overrides/` | variant / arch overrides |
| `Containerfile` | main image definition |
| `image.toml`, `iso.toml` | BIB configs |

## Debugging checklist

| Symptom | Check |
|---|---|
| build fails early | `just check && just lint` |
| missing command | `which just podman git` |
| package pulls fail | repo/network timeout; retry after failure completes naturally |
| storage errors | run `just clean`, verify free disk |
| permission issues | some build paths require sudo/root |
| NVIDIA driver version mismatch in GDX | Pass explicit `fedora_akmods_version=NN` to `just build` |

Recovery loop:

```bash
just clean
just check && just lint
just build bluefin lts
```
