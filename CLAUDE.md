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

**`buildchain/versions.mk`** lists line, version, Alpine base, and a per-line
status note (which subpackages are omitted, which patches a line needs, module
counts for the ancient lines). `make list` renders it. Its status notes are the
best summary of *why* a line looks the way it does.

> **It is hand-maintained, and nothing keeps it in sync.** No workflow or script
> writes it - `build-git-daily.yml` and `scripts/discover-releases.sh` bump
> `packages/<line>/APKBUILD` only. **The APKBUILDs are the source of truth for
> versions**; `versions.mk` is a status/display file that drifts. The `git` row
> is stale by construction, since that line is re-pinned daily. Two known
> mismatches that are *not* drift: `22-cert` is `22.8-cert3` here (upstream
> naming) but `22.8.0.3` as a pkgver (apk-sortable), and the `git` row lags the
> current snapshot.

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

### Single-line convenience path

`make build` (= `build-docker` + `init-keys` + `build-packages` + `repo-index`)
carries one line end to end. It defaults to line 20; override with
`M0_LINE=<line>`. The announced version is read from that line's APKBUILD, and
`repo-index` honours `ALPINE_VERSION`, so `ALPINE_VERSION=edge` works here too.

Prefer the per-line targets above when you know which line you want - this path
exists because it predates them.

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

Alpine's own `main` repo ships `asterisk` **22.9** plus `-fax`/`-odbc`/`-tds`,
so the package names overlap with ours. The `@andrius-asterisk` pin tag resolves
that overlap on every line **except one case**: `apk-tools 3` cannot select
`asterisk-tds=1.6.2.24-r0` and aborts with

```
asterisk-tds-22.9.0-r0: breaks world[asterisk-tds=1.6.2.24-r0@andrius-asterisk]
```

**Do not try to fix this with pinning.** `@tag`, `=version`, `--repository`,
seeding `world`, disabling `main`, and pre-installing `freetds` all fail
identically - it is an apk3 solver limitation, not a repository-priority
problem. The workaround is to omit `asterisk-tds` on the 1.6 line.

The blast radius is exactly one package at one version. Verified on a clean
`alpine:3.24` (apk-tools 3.0.6) on 2026-07-22:

- `asterisk-tds` installs fine at **1.8.32.3, 16.30.1, 20.20.1**
- `asterisk`, `-fax`, `-odbc`, `-sample-config`, `-sounds-en` install fine at
  **1.6.2.24**
- only `asterisk-tds` at **1.6.2.24** fails

> An earlier version of this note claimed every line older than 22.9 lost the
> overlapping subpackages to the official build. That is **wrong** - 1.8 and 16
> resolve `asterisk-tds` without trouble. Do not reintroduce that explanation.

The in-repo smoke test is unaffected: it installs via `--repository /repo` with
exact pins and does not pull the `-tds` subpackage.

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
