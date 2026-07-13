# Buildchain Documentation

A complete Docker-based buildchain for compiling Asterisk PBX packages for Alpine Linux.

> This document covers the **buildchain internals** - how the packages are built,
> signed, and published. If you just want to *install* Asterisk, see the
> [main README](../README.md). For the exact version matrix see
> [`buildchain/versions.mk`](../buildchain/versions.mk); for the CI/publish
> pipeline see [`docs/github-actions-buildchain-design.md`](github-actions-buildchain-design.md).

## Overview

This repository provides:

- **Docker-based build environment** for creating APK packages with Alpine's `abuild`
- **Official Alpine APKBUILDs** for multiple Asterisk lines (23, 22, 22-cert, 20, 18, 16, git) on Alpine 3.24
- **~20 Asterisk subpackages per line** (core, codecs, database connectors, etc.)
- **Signed APK repository** infrastructure (`repository/v3.24/main/x86_64/`)
- **Automated build + test** via Makefile, and a GitHub Actions pipeline that publishes to GitHub Pages

Each Asterisk line is defined by its own `packages/<line>/APKBUILD`. One Alpine
base (3.24) is used for every line, so the build result is a "failure frontier":
which Asterisk versions survive the modern toolchain and which break.

## Features

### Asterisk subpackages built

Each line is split into the standard Alpine Asterisk subpackages, e.g.:

**Core:** `asterisk`, `asterisk-dev`, `asterisk-doc`, `asterisk-sample-config`
**Codecs:** `asterisk-opus`, `asterisk-speex`
**Database & directory:** `asterisk-pgsql`, `asterisk-ldap`, `asterisk-odbc`, `asterisk-tds`
**Features:** `asterisk-curl`, `asterisk-fax`, `asterisk-mobile`, `asterisk-srtp`, `asterisk-alsa`, `asterisk-prometheus`
**Media:** `asterisk-sounds-moh`, `asterisk-sounds-en`
**System:** `asterisk-openrc`

Some older lines omit a few subpackages where the modern toolchain drops a
feature; see `buildchain/versions.mk` for the per-line result notes.

## Quick Start

### Prerequisites

- Docker or Podman
- Make
- 2GB+ free disk space

### Build one line

```bash
make build-23          # Asterisk 23 (current)
make build-22          # Asterisk 22 (LTS)
make build-22-cert     # Asterisk 22.8 (certified)
make build-20          # Asterisk 20
```

### Build a tier

```bash
make build-modern      # 20 + 22 + 22-cert + 23
make build-full        # 23 22 22-cert 20 18 16 git
```

### Test a built line

```bash
make test-23           # install the built 23.x apks in a container and verify
make test-all          # test every green line
```

## Directory Structure

```
asterisk-alpine/
├── docker/
│   ├── builder.Dockerfile     # Build environment (Alpine 3.24 + alpine-sdk)
│   └── test.Dockerfile        # Runtime test image
├── buildchain/
│   └── versions.mk            # The line -> version -> result matrix
├── packages/
│   └── <line>/                # one dir per Asterisk line
│       ├── APKBUILD           # Package build recipe
│       ├── *.patch            # Alpine musl patches
│       └── *.initd/confd      # Init scripts
├── scripts/
│   ├── build.sh                # Build orchestration (runs abuild -r)
│   ├── ci-install-signing-key.sh  # CI: materialise the signing key
│   ├── init-keys.sh            # Local key generation
│   └── build-repo-index.sh     # Repository index generator
├── repository/                 # Built packages output
│   └── v3.24/main/x86_64/
│       ├── APKINDEX.tar.gz
│       └── asterisk*.apk
├── keys/                       # RSA signing keys (not in git)
├── .github/workflows/ci.yml    # Build + test + publish to Pages
├── docker-compose.yml
├── Makefile
└── docs/BUILDCHAIN.md          # (this file)
```

## Build Process Details

### 1. Initialize Signing Keys

Generate RSA keys for signing packages:

```bash
make init-keys
```

This creates:

- `keys/packages@asterisk-alpine.rsa` - Private key (keep secure!)
- `keys/packages@asterisk-alpine.rsa.pub` - Public key (distribute to users)

**IMPORTANT:** Never commit private keys to git.

### 2. Build Packages

For a given line, the build process:

1. Starts the Alpine 3.24 builder container
2. Installs the build dependencies
3. Downloads the Asterisk source
4. Applies Alpine's musl compatibility patches
5. Configures with the line's feature set
6. Compiles Asterisk
7. Splits into subpackages
8. Signs all packages with your key and writes them to `repository/v3.24/main/x86_64/`

```bash
make build-23
```

**Build time:** ~3-5 minutes per line on CI hardware; longer on a laptop.

### 3. Create Repository Index

The per-line build regenerates the index automatically. To rebuild it by hand:

```bash
make repo-index-22     # regenerate + sign repository/v3.24/main/x86_64/APKINDEX.tar.gz
```

### 4. Test Repository (Optional)

Start a local nginx server hosting your repository:

```bash
make repo-server
# Access at http://localhost:8080/v3.24/main/x86_64/
```

## Using Your Custom Repository

See the [main README](../README.md#install) for the client-side install, including
the repository pinning that keeps these packages from clashing with Alpine's own
`asterisk`.

### Self-Signed Packages (Testing)

To install a single `.apk` without trusting the key:

```bash
apk add --allow-untrusted asterisk-23.4.1-r0.apk
```

## Makefile Targets

```bash
make help            # Show all available targets
make list            # Show the build matrix from buildchain/versions.mk
make build-<line>    # Build one line (23, 22, 22-cert, 20, 18, 16, git)
make build-modern    # Build 20 + 22 + 22-cert + 23
make build-full      # Build all eight green lines
make test-<line>     # Install + verify one built line
make test-all        # Test every green line
make repo-index-22   # Regenerate + sign the v3.24 index
make init-keys       # Generate RSA signing keys
make shell-22        # Shell into a builder container
make validate-22     # abuild sanitycheck an APKBUILD
make clean           # Clean build artifacts
make clean-all       # Clean everything including keys
```

## Development Workflow

### Modify a line's package configuration

Edit `packages/<line>/APKBUILD` to change the version, configure flags, features,
or patches, then:

```bash
make validate-22     # Check syntax
make build-22        # Rebuild
```

Checksums are regenerated by `abuild checksum` during the build.

### Add a custom patch

1. Place the patch file in `packages/<line>/`
2. Add its filename to the `source=` array in that APKBUILD
3. Rebuild the line (checksums update automatically)

## Continuous Integration

`.github/workflows/ci.yml` builds, smoke-tests, signs, and publishes the repo:

- **setup** picks the line matrix + a publish flag + a tier from the trigger
- **build** builds and `test`s each line in a matrix, uploading per-line apk artifacts
- **frontier** attempts line 14 (known-broken older release) with `continue-on-error` on full builds
- **publish** signs the merged index and deploys the repo to GitHub Pages (on push to `main`/tags only)

See [`docs/github-actions-buildchain-design.md`](github-actions-buildchain-design.md)
for the full design.

## Security Considerations

1. **Private key security** - never commit `keys/*.rsa`; store it in a secret
   manager; in CI it comes from the `ABUILD_PRIVATE_KEY` secret.
2. **Package signing** - packages are always signed; distribute the public key
   over HTTPS; clients verify signatures on install.
3. **Build environment** - review each APKBUILD before building; use trusted
   source tarballs.

## Troubleshooting

### Build fails with "Permission denied"

- Ensure scripts are executable: `chmod +x scripts/*.sh`
- Check the Docker daemon is running

### "Signing keys not found"

- Run `make init-keys` first

### Packages not found after build

- Check `repository/v3.24/main/x86_64/`
- Run `make info` to see the package count

### Docker not available

- Install Docker: `curl -fsSL https://get.docker.com | sh`
- Or use Podman: `alias docker=podman`

## Resources

- [Alpine Linux Packages](https://pkgs.alpinelinux.org/)
- [Alpine APKBUILD Reference](https://wiki.alpinelinux.org/wiki/APKBUILD_Reference)
- [Alpine repository pinning](https://wiki.alpinelinux.org/wiki/Repository_pinning)
- [Asterisk Documentation](https://docs.asterisk.org/)
- [abuild Manual](https://wiki.alpinelinux.org/wiki/Abuild_and_Helpers)

## License

This buildchain configuration is provided as-is for building Asterisk packages.

- Asterisk is GPL-2.0-only WITH OpenSSL-Exception
- Alpine Linux APKBUILD files maintain their original licenses
- Build scripts in this repository: MIT License
