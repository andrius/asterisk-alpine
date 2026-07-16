# Asterisk Alpine Linux Buildchain

Signed Alpine Linux **apk packages for multiple Asterisk versions**, built from
official Alpine APKBUILDs on Alpine 3.24 and published as a ready-to-use apk
repository on **[Cloudsmith](https://cloudsmith.io/~asterisk/repos/alpine/)**
(`asterisk/alpine`).

[![Hosted By: Cloudsmith](https://img.shields.io/badge/OSS%20hosting%20by-cloudsmith-blue?logo=cloudsmith&style=for-the-badge)](https://cloudsmith.com)

Available lines (each built and smoke-tested in CI): **23** (current), **22**
(LTS), **22-cert** (certified), **20**, plus **18 / 16** (LTS, EOL) and the
**git** line (master snapshot, best-effort). The LTS `22.10` and certified
`22.8` builds coexist in the same repository. Ancient **1.6** and **1.8**
build too (musl module-load patched) for archaeology.

**Architectures:** x86_64, aarch64 (Apple Silicon / RPi 4-5 / Graviton), and
armv7 / armhf (32-bit Raspberry Pi). The same repo line works everywhere - apk
resolves packages for the running architecture automatically.

## Install

```sh
# 1. Trust the repository signing key
wget -O /etc/apk/keys/alpine@asterisk-25B0C9A992BE0CEF.rsa.pub \
  https://dl.cloudsmith.io/public/asterisk/alpine/cfg/rsa/rsa.25B0C9A992BE0CEF.key

# 2. Add the repo under a pin tag (see "Avoiding conflicts" below)
echo "@andrius-asterisk https://dl.cloudsmith.io/public/asterisk/alpine/alpine/v3.24/main" \
  >> /etc/apk/repositories

# 3. Install the line you want, pinned to this repo
apk add "asterisk@andrius-asterisk=~23"      # 23.x  current
apk add "asterisk@andrius-asterisk=~22"      # 22.x  LTS (22.10)
apk add "asterisk@andrius-asterisk=~22.8"    # 22.8  certified
apk add "asterisk@andrius-asterisk=~20"      # 20.x
```

The **git** line (a build of Asterisk `master`, may be unstable) sorts highest,
so an unpinned `apk add asterisk@andrius-asterisk` installs it. Pin a version
as above for a release.

### Alpine edge

The newest lines (22, 23, git) are also built against Alpine **edge** under a
second pin tag - for early adopters. Edge rolls daily, so these packages are
unstable. The signing key above covers this too (same Cloudsmith repository).

```sh
echo "@andrius-asterisk-edge https://dl.cloudsmith.io/public/asterisk/alpine/alpine/edge/main" \
  >> /etc/apk/repositories
apk add "asterisk@andrius-asterisk-edge=~23"
```

### Avoiding conflicts with Alpine's asterisk

Alpine ships its **own** `asterisk` (`22.9` in the always-enabled `main` repo),
so the package names overlap. The `@andrius-asterisk` **pin tag** above makes apk take
asterisk from this repository only, and stops `apk upgrade` from silently
swapping it for Alpine's build. The `=~22.8` version match additionally isolates
the certified line from the LTS and from Alpine's `22.9`.

Full explanation and per-line details:
[examples/README.md](examples/README.md#avoiding-conflicts-with-alpines-asterisk).

## Docker examples

Ready-to-build images live in [`examples/`](examples/):

- [`examples/asterisk-23/`](examples/asterisk-23/) - Asterisk 23 (current)
- [`examples/asterisk-22-cert/`](examples/asterisk-22-cert/) - Asterisk 22.8 (certified)

A minimal image is just:

```dockerfile
FROM alpine:3.24
ADD https://dl.cloudsmith.io/public/asterisk/alpine/cfg/rsa/rsa.25B0C9A992BE0CEF.key \
    /etc/apk/keys/alpine@asterisk-25B0C9A992BE0CEF.rsa.pub
RUN echo "@andrius-asterisk https://dl.cloudsmith.io/public/asterisk/alpine/alpine/v3.24/main" >> /etc/apk/repositories \
 && apk add --no-cache "asterisk@andrius-asterisk=~23" "asterisk-sample-config@andrius-asterisk=~23"
CMD ["asterisk", "-fvvv"]
```

## Package hosting

Package repository hosting is graciously provided by [Cloudsmith](https://cloudsmith.com).
Cloudsmith is the only fully hosted, cloud-native, universal package management
solution, that enables your organization to create, store and share packages in
any format, to any place, with total confidence.

## Building it yourself

This repository also contains the full Docker buildchain that produces these
packages - the `abuild` pipeline, package signing, the multi-version build
matrix, and the GitHub Actions publish-to-Cloudsmith flow. See
**[docs/BUILDCHAIN.md](docs/BUILDCHAIN.md)**.

## License

- Asterisk is GPL-2.0-only WITH OpenSSL-Exception
- Alpine Linux APKBUILD files maintain their original licenses
- Build scripts in this repository: MIT License

---

**Built with ❤️ for the Asterisk and Alpine Linux communities**
