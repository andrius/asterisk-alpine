# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker-based buildchain that compiles **multiple Asterisk lines** into signed
Alpine Linux apk packages using Alpine's native `abuild` tooling, and publishes
them to **Cloudsmith**.

The build matrix, not any single package, is the product. Ten lines are built
from ten independent APKBUILD directories under `packages/`:

| Line | pkgver | Tier | Arches |
|---|---|---|---|
| `23` | 23.4.1 | modern (current) | x86_64, aarch64, armv7, armhf |
| `22` | 22.10.1 | modern (LTS) | x86_64, aarch64, armv7, armhf |
| `22-cert` | 22.8.0.3 | modern (certified) | x86_64, aarch64, armv7, armhf |
| `20` | 20.20.1 | modern | x86_64, aarch64 |
| `18` | 18.26.4 | legacy (EOL LTS) | x86_64, aarch64 |
| `16` | 16.30.1 | legacy (EOL LTS) | x86_64, aarch64 |
| `14` | 14.7.8 | frontier (best-effort) | x86_64 |
| `1.8` | 1.8.32.3 | ancient | x86_64 |
| `1.6` | 1.6.2.24 | ancient | x86_64 |
| `git` | 24.0.0_git<date> | master snapshot (best-effort) | x86_64, aarch64 |

Base is **Alpine 3.24** (`ALPINE_VERSION ?= v3.24`). The newest lines (22, 23,
git) are additionally built against **Alpine edge** as a canary.

> Each line is self-contained: its own `APKBUILD`, its own musl patch set, its
> own subpackage split. Patch drift between lines is expected and normal - do
> not try to unify them.

## Environment Setup

Run all commands from the repository root. Builds run inside the isolated
Alpine builder containers; nothing is compiled on the host.

## Architecture

### Build flow

1. **Builder containers** (`docker/builder.Dockerfile`, one compose service per
   line: `builder-20`, `builder-23`, `builder-1.6`, `builder-git`,
   `builder-22-edge`, ...). Alpine base + `alpine-sdk`/`abuild`, running as the
   non-root `builder` user (an abuild requirement).

2. **APKBUILD processing** (`packages/<line>/APKBUILD`). Each builds a core
   package plus its subpackage split (codecs, DB connectors, sounds, `-dev`,
   `-doc`, ...) from one source tarball, applying that line's musl patches.

3. **Signing.** `abuild` signs with the RSA key in `keys/` (`make init-keys`
   generates it). `keys/*.rsa` is gitignored - never commit a private key.

4. **Local repository** (`repository/v3.24/main/<arch>/` plus `noarch/`).
   `apk` 3.x fetches noarch packages from `<repo>/noarch/`, so that tree must
   exist or noarch installs 404.

### Volume mounts (per builder service)

```
./packages/<line> → /home/builder/main/asterisk   (APKBUILD + patches)
./repository      → /home/builder/packages        (output APKs)
./keys            → /home/builder/.abuild         (signing keys)
./scripts         → /home/builder/scripts         (ro)
```

## Common Commands

### Per line (the normal path)

```bash
make build-23           # build one line (also: build-22, build-20, build-1.6, build-git, ...)
make test-23            # install the built apk in a container and verify asterisk -V
make shell-23           # shell inside that line's builder
make validate-23        # APKBUILD syntax check (only 22 and 23 have this)
make list               # show the build list with per-line status notes
make help               # all targets
```

`build-<line>`, `test-<line>` and `shell-<line>` exist for every line;
`validate-<line>` only for 22 and 23.

The build list itself lives in **`buildchain/versions.mk`** - line, pkgver,
Alpine base, and a per-line status note (which subpackages are omitted, which
patches a line needs, module counts for the ancient lines). That file, not this
table, is the source of truth when they disagree.

### Groups

```bash
make build-modern       # 20 + 22 + 22-cert + 23
make build-full         # modern + 18 + 16 + git
make test-all           # smoke-test every green line
```

`build-full` deliberately excludes `14`, `1.8`, `1.6` - build those explicitly.

### Alpine edge

```bash
make build-23 ALPINE_VERSION=edge
```

`ALPINE_VERSION` selects the repo dir (`v3.24` or `edge`) and the image tag.

### Keys, index, cleanup

```bash
make init-keys          # generate the RSA signing key (once)
make repo-index         # regenerate APKINDEX.tar.gz
make clean              # remove src/ and pkg/ build artifacts
make clean-all          # also remove keys
```

### Smoke tests

`scripts/test-run.sh` installs the freshly built apk from the local repo
(`--repository /repo` + an exact `=<ver>-r0` pin) and asserts `asterisk -V`.
`SMOKE_LEVEL` is `full` natively and `version` under emulation - QEMU cannot
reliably run the daemon for 32-bit ARM, so those legs check the version only.
Certified builds report `certified-22.8-certN` rather than the pkgver, so
`test-22-cert` runs with `RELAXED=1`; `test-1.6`, `test-1.8` and `test-git` do
too.

> **Legacy `make build` / `build-packages` / `repo-index` targets are stale.**
> They date from the original single-package layout and still announce
> "Alpine 3.22" / "Asterisk 20.11.1", with `repo-index` hardcoding
> `ALPINE_VERSION=v3.22`. They now operate on `builder-20`. Prefer the per-line
> targets above; treat these as unreconciled.

## Publishing (CI, not `make`)

Packages are published to **Cloudsmith** (`asterisk/alpine`) by GitHub Actions -
the local `make` flow only produces a local `repository/` tree.

- `ci.yml` - stable, `alpine_version: v3.24`. Modern tier on push/PR; full tier
  weekly (Mon) and on dispatch. Ancient 1.6/1.8 gate every run (x86_64).
- `build-edge.yml` - `alpine_version: edge`, weekly canary, `allow_fail`.
- `build-git-daily.yml` - daily; skips when upstream `master` still matches the
  `_gitrev` pinned in `packages/git/APKBUILD`, then commits the new pin.
- `discover-releases.yml` - daily upstream poll, opens a version-bump PR.
- `_build.yml` / `_publish.yml` - reusable workflows both callers share.

Cloudsmith owns indexing, signing (its own key, fingerprint
`25B0C9A992BE0CEF`), CDN and retention. Distributions: `alpine/v3.24` and
`alpine/edge`. Publishing uses `--republish`; without it, re-runs create failed
duplicate uploads that shadow the completed copies and every download 404s.

> GitHub Pages (`apk.andrius.mobi`, `abuild`-signed) was the previous registry;
> retired 2026-07 in favour of Cloudsmith.

### CI secrets

- `CLOUDSMITH_API_KEY` - required; pushes to Cloudsmith.
- `ABUILD_PRIVATE_KEY`, `ABUILD_KEY_NAME` - sign packages during the build.
- `BLOG_DISPATCH_TOKEN` - notifies the andrius.mobi timeline.
- `ASTERISK_DISPATCH_TOKEN` - **not currently set.** The `notify-consumer` job
  needs it to poke `andrius/asterisk`; without it the job exits 0 and reports
  *success* while doing nothing.

Local credentials live in `.ai-secrets.md` (gitignored, never committed).

## Development Workflow

### Modifying an APKBUILD

1. Edit `packages/<line>/APKBUILD`.
2. `make validate-<line>` for syntax.
3. `make build-<line>` - `abuild checksum` regenerates sha512 automatically.
4. `make test-<line>`.

### Adding a patch

Drop the `.patch` in `packages/<line>/`, add it to that line's `source=` array,
rebuild. Only patch the lines that need it.

### Common musl patches

`10-musl-mutex-init.patch`, `20-musl-astmm-fix.patch`, `40-asterisk-cdefs.patch`,
`41-asterisk-ALLPERMS.patch`, `gethostbyname_r.patch`. Which apply varies by
line - Asterisk 23 dropped the `db1-ast` hunk that older lines still need. Two
extra musl fixes (recursive-mutex static init, dlclose loop) are what make 1.6
and 1.8 load all modules at all.

## Consumer notes

Alpine's own `main` repo ships `asterisk` **22.9** plus `-fax`/`-odbc`/`-tds`.
Package names therefore overlap with ours. The `@andrius-asterisk` pin tag
handles this for lines at or above 22.9, but **not** for older lines: apk still
prefers the higher official version and aborts, e.g.

```
asterisk-tds-22.9.0-r0: breaks world[asterisk-tds=1.6.2.24-r0@andrius-asterisk]
```

Core + `asterisk-sample-config` install fine on every line; the overlapping
subpackages are the problem. The in-repo smoke test is unaffected because it
installs via `--repository /repo` with exact pins.

`chan_websocket` (upstream 20.16.0 / 22.6.0 / 23.0.0) is present on 20, 22, 23
and git; absent on 18, 16, 14, 1.8, 1.6. It ships in the main package - there is
no separate subpackage.

## Security Notes

1. **Never commit private keys** - `keys/*.rsa` is gitignored.
2. Signing is mandatory; abuild refuses unsigned builds.
3. The builder runs as non-root; abuild refuses to run as root.
4. Users verify with the public key served by Cloudsmith.

## Troubleshooting

- **"Signing keys not found"** - run `make init-keys`.
- **"abuild refuses to run as root"** - use the compose services; they already
  run as `builder`.
- **Permission denied on scripts** - `chmod +x scripts/*.sh`.
- **No packages produced** - check `repository/v3.24/main/<arch>/`, then the
  build log for compile errors.
- **noarch package 404s** - the `noarch/` tree wasn't published.
