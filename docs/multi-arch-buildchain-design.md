# Multi-Architecture Buildchain - Design

**Date:** 2026-07-07
**Status:** approved (brainstorm), pending implementation plan

## Goal

Extend the Asterisk-on-Alpine buildchain to publish signed apk packages for
**x86_64, aarch64, armv7, and armhf**, built entirely in GitHub Actions, so the
same repository (`apk.andrius.mobi`) serves the right packages to x86_64 hosts,
Apple Silicon Macs and 64-bit ARM boards (aarch64), and 32-bit Raspberry Pi
(armv7 / armhf) transparently.

## Background

- Every line's `APKBUILD` is already `arch="all"`, and `abuild` writes packages
  to `$REPODEST/main/$CARCH/`. Running the *same* builder container as a
  different platform therefore produces packages for that arch with no
  build-script changes.
- The Opus codec is **not** the usual blocker. Alpine's asterisk (our APKBUILD)
  builds `codec_opus_open_source.so` from the open-source
  [traud/asterisk-opus](https://github.com/traud/asterisk-opus) sources against
  the system `libopus` (`opus-dev`) - portable C, not the proprietary
  x86_64-only Sangoma blob. It should compile on ARM like any other module.
- GitHub provides free native `ubuntu-24.04-arm` runners for public repos (GA
  Aug 2025), so aarch64 builds run natively. There is **no** native 32-bit ARM
  runner, so armv7/armhf must build under QEMU emulation.

## Architecture: QEMU-emulated native builds

Reuse the existing `abuild`-in-an-Alpine-container flow unchanged, varying only
the platform the builder container runs as:

| Arch | Runner | Platform | Speed |
|---|---|---|---|
| x86_64 | `ubuntu-latest` | native (amd64) | fast |
| aarch64 | `ubuntu-24.04-arm` | native (arm64) | fast |
| armv7 | `ubuntu-latest` + QEMU | `linux/arm/v7` | slow (emulated) |
| armhf | `ubuntu-latest` + QEMU | `linux/arm/v6` (Alpine armhf = ARMv6) | slow (emulated) |

Rejected alternatives:

- **abuild cross-compilation (`abuild -a`)** - faster than QEMU but fragile for
  a large C project with ~35 build deps; high risk, much new machinery.
- **buildx multi-platform image build** - applies to container images, not apk
  packages. Not a fit.

## Build matrix (arch x line x trigger)

| Trigger | x86_64 | aarch64 | armv7 | armhf |
|---|---|---|---|---|
| PR / push-to-`main` (modern) | 20, 22, 22-cert, 23 | 20, 22, 22-cert, 23 | - | - |
| tag / `workflow_dispatch` (full) | all 8 lines | all 8 lines | 22, 23 (+22-cert best-effort) | 22, 23 (+22-cert best-effort) |

Rules:

- Native arches (x86_64, aarch64) build on every trigger, same tier logic as today.
- 32-bit arches (armv7, armhf) build only on tag/dispatch, and only lines **22
  and 23** as targets, plus **22-cert as best-effort** (`continue-on-error`: a
  build or test failure is recorded, publishes nothing for that combo, and does
  not fail the workflow). Line 20 is **not** attempted on 32-bit.
- Every 32-bit combo is `continue-on-error` in the spirit of the failure frontier.

## Repository layout & client experience

Alpine-native per-arch layout plus the shared `noarch/` tree:

```
apk.andrius.mobi/v3.24/main/
|- x86_64/    APKINDEX.tar.gz + all 8 lines
|- aarch64/   APKINDEX.tar.gz + all 8 lines
|- armv7/     APKINDEX.tar.gz + 22, 23 (+22-cert if it passes)
|- armhf/     APKINDEX.tar.gz + 22, 23 (+22-cert if it passes)
|- noarch/    sample-config, doc, sounds, openrc (arch-independent, one copy)
```

Client experience is unchanged and automatic - apk fetches
`<base>/v3.24/main/<system-arch>/APKINDEX`, so the same repo line works
everywhere:

```sh
echo "@andrius-asterisk https://apk.andrius.mobi/v3.24/main" >> /etc/apk/repositories
apk add "asterisk@andrius-asterisk=~23"
```

- x86_64 host -> x86_64 packages
- Apple Silicon Mac (Docker) / RPi 4-5 / Graviton -> aarch64
- 32-bit Raspberry Pi -> armv7 (or armhf on Pi 1 / Zero)

The existing example Dockerfiles then work on Apple Silicon with no change:
`docker build` on an arm64 host pulls the arm64 Alpine base and installs aarch64
asterisk.

`noarch/` packages (config/docs/sounds/openrc) are arch-independent and identical
across builds, so a single copy is published (taken from the x86_64 build, which
always runs); every arch's index references them at the shared `noarch/` path.

## Pin tag rename

The repository pin tag changes from `@astalpine` to **`@andrius-asterisk`**
(verified: apk accepts dashes in tags). This must be updated everywhere it
already appears: `README.md`, `examples/README.md`,
`examples/asterisk-23/Dockerfile`, `examples/asterisk-22-cert/Dockerfile`, and
the publish job's generated `index.html`.

## CI structure

### `setup` job

Emits a JSON matrix of build combos, each carrying its own runner + platform +
best-effort flag, computed from the trigger:

```
{ line: "23", arch: "aarch64", runner: "ubuntu-24.04-arm", platform: "",            allow_fail: false }
{ line: "23", arch: "armv7",   runner: "ubuntu-latest",    platform: "linux/arm/v7", allow_fail: false }
{ line: "22-cert", arch: "armhf", runner: "ubuntu-latest", platform: "linux/arm/v6", allow_fail: true  }
```

### `build` job

- `runs-on: ${{ matrix.runner }}`, `continue-on-error: ${{ matrix.allow_fail }}`,
  `strategy.fail-fast: false`.
- Steps: register QEMU binfmt via `docker/setup-qemu-action` **only when**
  `matrix.platform` is set -> install signing key -> make bind-mounted dirs
  writable -> `DOCKER_DEFAULT_PLATFORM=${{ matrix.platform }} make build-<line>`
  -> `make test-<line>` (runs `asterisk -V` in a container of that arch; under
  QEMU for 32-bit) -> upload `apks-<arch>-<line>` from
  `repository/v3.24/main/<arch>/`.
- No build-script changes: `abuild` keys off `$CARCH` and writes to the correct
  arch directory automatically.

### `frontier` job

Unchanged in spirit (lines 14, 13). Native arches only.

### `publish` job

- Download every `apks-*` artifact into its `repository/v3.24/main/<arch>/`.
- Run `build-repo-index.sh` **once per arch** (each produces that arch's signed
  `APKINDEX`); `build-repo-index.sh` already takes `ARCH`, so this is a loop.
- Mirror `noarch/` once (from the x86_64 tree).
- Assemble `_site` with all arch dirs + `noarch/` + pubkey + `CNAME` + index.html.
- Deploy to Pages (unchanged mechanism).

## Testing

- Native arches (x86_64, aarch64) run the existing smoke test (`asterisk -V`) at
  full speed.
- 32-bit arches run the same smoke test under QEMU (slower).
- A 22-cert 32-bit build/test failure is non-fatal (`allow_fail`) - it publishes
  nothing for that combo and is logged as a frontier entry.

## Results tracking

Extend `buildchain/versions.mk` (or add a companion `arch-matrix.mk`) to record
per-`(line, arch)` result (green / broken + reason), and note the arch coverage
in `ROADMAP.md`. The "failure frontier" becomes two-dimensional (line x arch).

## Global constraints

- Single Alpine base: **3.24**; repo path `v3.24/main/<arch>/`; pin tag
  `@andrius-asterisk`; signing key `packages@asterisk-alpine.rsa` from the
  `ABUILD_PRIVATE_KEY` secret.
- No AI / co-author attribution in commits, code, or messages.
- No em-dashes or en-dashes anywhere (plain hyphen only).
- `git commit --no-gpg-sign`.
- Docs/examples-only changes should not trigger the expensive build - the
  implementation should add `paths-ignore` (`**.md`, `docs/**`, `examples/**`)
  to the `push` trigger.

## Out of scope

- Native macOS / Homebrew Asterisk (different toolchain).
- Alpine arches beyond the four above (x86, ppc64le, s390x, riscv64).
- 32-bit builds of the ancient lines (18/17/16/15/14/13) and line 20.
