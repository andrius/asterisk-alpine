# Asterisk Alpine - Multi-Version Build Suite Roadmap

> Build and deliver **multiple Asterisk PBX versions** (1.8, 10, 11, 13, 16, 18, 20, 22, 23)
> as native Alpine Linux (`apk`) packages, each on the most appropriate Alpine base,
> from a single reproducible Docker buildchain.

Reference date: 2026-07-05. Research sources are listed at the bottom.

---

## 1. Why this is harder than "just build more versions"

Asterisk is a 25-year-old C codebase that assumes **glibc**. Across the version range we
target, three independent axes move at once, and each axis has failure modes on Alpine
(musl) that must be handled per-version:

| Axis | Modern (18/20/22/23) | Legacy (16/13) | Ancient (11/10/1.8) |
|------|----------------------|--------------------------|----------------------|
| **libc** | musl patches exist & maintained in aports | musl patches exist but older | glibc-only; musl unaware |
| **OpenSSL** | 3.x native | upstream wants **1.1.x**; 3.0 may break PJSIP TLS/SRTP | upstream wants **1.0.x** |
| **PJSIP** | bundled or system `pjproject-dev` | bundled pjproject (`--with-pjproject-bundled`, since 13.8.0) | **none** - chan_sip only (PJSIP arrived in Asterisk 12) |
| **chan_sip** | dropped from default build in **22** | default | only SIP stack |

**Decision (revised 2026-07-05):** build **every** version on the **single latest Alpine
(3.24)** - OpenSSL 3, musl, gcc 15. The deliverable is the **failure frontier**: which
versions survive the modern toolchain and which break, with each break documented. We do
**not** fall back to period-appropriate bases; an old version that won't build on 3.24 is
recorded as a failure with a root cause, not silently rescued. This keeps the suite on one
maintainable base and surfaces real compatibility limits.

---

## 2. The build list (single base: Alpine 3.24)

Every row attempted on Alpine 3.24. `result` is the outcome of that attempt.

| Asterisk | Type | Latest point rel. | EOL | Result on 3.24 | Notes |
|----------|------|-------------------|-----|----------------|-------|
| **23** | Standard | 23.4.1 | current | ✅ ok | 19 APKs, verified |
| **22** | LTS | 22.10.1 | current LTS | ✅ ok | 19 APKs, verified |
| **22-cert** | Certified LTS | 22.8-cert3 | current certified | ✅ ok | 15 APKs (pgsql/ldap/tds/prometheus subpkgs omitted - modules don't build on libpq 18 / certified 22.8) |
| **20** | LTS | 20.20.1 | SFO 2026-10 | ✅ ok | 20 APKs, verified |
| **18** | LTS | 18.26.4 | sec-only → 2026-10 | ✅ ok | 17 APKs (pgsql/ldap/prometheus omitted); DAHDI/libpri dropped from aports, disabled in configure |
| **16** | Certified LTS | 16.30.1 | EOL 2023 | ✅ ok | 17 APKs, verified |
| **git** | dev | master snapshot | rolling | 🟡 best-effort | full tier only; `make build-git` pins _gitrev via scripts/git-snapshot.sh |
| **14** | Standard | 14.7.8 | EOL | ✅ ok | 17 APKs - patched pj_in_addr + srtp GCM keysize |
| **12** | Standard | 12.8.2 | EOL | ❌ fail (expected) | PJSIP era; same or worse |
| **11** | LTS | 11.25.3 | EOL 2017 | ❌ fail (expected) | pre-PJSIP; OpenSSL 1.0 era |
| **10** | Standard | 10.12.4 | EOL 2012 | ❌ fail (expected) | pre-PJSIP; OpenSSL 1.0 era |
| **1.8** | LTS | 1.8.32.3 | EOL 2015 | ⚠️ partial | **builds + packages** (10 APKs), `asterisk -V` works; **modules fail to load at runtime** (symbol relocation: `ast_module_register` etc. not found). Many fixes: OpenSSL 3 methods, `__P` macro, AST_INLINE_API, editline configure, gethostbyname_r rename |
| **1.6** | Standard | 1.6.2.24 | EOL 2012 | ❌ fail | compiles most of the tree; fails at bundled `aesopt.h` non-constant initializers (deep C-standards drift in AES crypto tables) |

### Failure frontier
**Asterisk 14.7.8 builds; 13.x is the first to fail at compile time.** The
blocker is a **pjproject API break** (patchable for 14.x) and db1-ast struct
changes. **1.8.32.3 compiles and packages** (10 APKs) with extensive patching
but its **modules can't load at runtime** - symbol relocation fails against the
core binary on the modern toolchain (`Error relocating app_playback.so:
ast_module_register: symbol not found`). **1.6 doesn't compile** (AES tables).
13.x fails even earlier - its bundled db1-ast (Berkeley DB) `HTAB` struct lost
the `mapp` member. Versions ≤12 are expected to fail the same or worse (older
PJSIP; ≤11 are pre-PJSIP, OpenSSL 1.0 era). Resurrecting ≤14 on modern Alpine
would require non-trivial backports of the pjproject API adaptation and db1-ast
struct changes - out of scope for this suite; recorded as the limit.
| **10** | Standard | 10.12.4 | EOL 2012 | ⬜ tbd | |
| **1.8** | LTS | 1.8.32.3 | EOL 2015 | ⬜ tbd | |

Architectures: **x86_64** first; aarch64 via buildx + QEMU binfmt later.

### Coexistence strategy
APK `pkgname` stays `asterisk` for every line. Versions that build coexist by **repo path**:
`repository/v3.24/main/<arch>/` holds every successfully-built version. (APK treats
`asterisk-22.10.1-r0` and `asterisk-20.20.1-r0` as two versions of one package - a user
pins the one they want.) Older EOL lines ship with a clear description suffix.

---

## 3. Goals (deep)

**G1 - Coverage.** Deliver native `apk` packages for all nine Asterisk lines above, each on
its compatible Alpine base, with the standard subpackage set (core, dev, doc, codecs,
DB connectors, fax, srtp, sounds, openrc, …) appropriate to that line's era.

**G2 - Reproducibility.** One command (`make build-VERSION` / `make build-all`) builds any
subset, idempotently, in Docker, with deterministic-enough output (pinned sources, checksums,
signed index). No "works on my machine."

**G3 - Honesty about EOL.** Every package carries its real security status (secfixes block,
description suffix). Ancient lines (1.8/10/11) are flagged **best-effort / unsupported - for
legacy interop only**. The repo UI and docs make the risk visible, not hidden.

**G4 - One entrypoint, many targets.** A single Makefile matrix: `make list`, `make build-20`,
`make build-all-modern`, `make build-all`, `make test-20`, `make repo-index-all`. Tiers are
first-class so you can build only the modern set in CI and skip the expensive ancient
toolchains by default.

**G5 - Smoke-tested, not just compiled.** Each built version is started in a runtime
container and probed: `asterisk -V`, core shows green, a SIP leg registers (chan_sip where
present, chan_pjsip on 22+), a channel executes a dialplan `Answer`. Build-green ≠ runs.

**G6 - Trackable & auto-bumpable.** Upstream Asterisk releases are tracked (RSS / GitHub
release poll); bumping a version is a one-line config change + `make bump-<line>` that
regenerates checksums. CVE history is maintained in each APKBUILD's `secfixes`.

**G7 - Multi-arch.** x86_64 and aarch64 for the modern tier at minimum; armv7 best-effort.

---

## 4. Milestones

Status legend: ✅ done · 🟡 in progress · ⬜ not started

### M0 - Foundation (current state) ✅
Single Asterisk **20.11.1-r6** builds on Alpine 3.22 via Docker + abuild, signs packages,
indexes the repo, runs in a test container. Proves the toolchain end-to-end.
- Deliverables: `docker/builder.Dockerfile`, `packages/asterisk/APKBUILD`, `scripts/`,
  `Makefile`, signing keys, repo index, runtime image.
- **Gap to close:** everything is hardcoded to one version and one Alpine base.

### M1 - Restructure for the matrix ✅
Turn the single-version repo into a version-parameterized buildchain without breaking M0.
- ✅ `packages/<line>/` per Asterisk line: `packages/22/`, `packages/23/` added (each
  self-contained: APKBUILD + patches + initd/confd/logrotate); `packages/asterisk/` kept
  as the 20.11.1 reference. *(That reference directory was deleted 2026-07-22 - it had
  been superseded by `packages/20/` and nothing built it. M0/M1 above describe the
  layout as it was at the time.)*
- ✅ `buildchain/versions.mk` - single source of truth mapping
  `line → {asterisk_ver, alpine_base, openssl, pjproject_mode, tier, status}`.
- ✅ `docker/builder.Dockerfile` parameterized by `ALPINE_VERSION` build-arg (one template).
- ✅ Makefile matrix: `build-22`, `build-23`, `build-20`, `build-modern`, `list`, `info`.
- ✅ Repo layout: `repository/v3.24/main/x86_64/` (REPODEST per Alpine base).
- **Findings that cost real time (record so we don't relearn):**
  1. **abuild 3.17 (Alpine 3.24) requires `/etc/apk/cache` to exist** or builddeps fail
     with `opening from cache ... No such file or directory` / `masked in: cache`. Fixed
     in the Dockerfile (`mkdir -p /etc/apk/cache`). abuild 3.15 (3.22) did not need this.
  2. **Maintainer line in APKBUILD must be RFC822-valid** (`# Maintainer: Name <a@b.tld>`);
     a bare hostname like `<x@asterisk-alpine>` fails `abuild validate` on 3.24.
  3. **Asterisk 22+ removed `chan_sip` from the source tree entirely** - not just
     disabled. `--enable chan_sip` in menuselect fails the build with `'chan_sip' not found`.
     PJSIP (`chan_pjsip`) is the only SIP stack from 22 onward.
  4. **abuild's `$repo` = parent dir of the APKBUILD.** Mount the APKBUILD tree at
     `/home/builder/main/asterisk` so `$repo=main` and packages land in `main/<arch>/`.
     Set `REPODEST=/home/builder/packages/v3.24` to version the output path.
  5. **The builder must trust its own public key** (`/etc/apk/keys/`) or the index step
     fails with `UNTRUSTED signature`. `build.sh` copies the pubkey in before `abuild -r`.

### M2 - Modern tier complete 🟡 (in progress)
Ship **18, 20, 22, 23** on current Alpine (3.24 stable, edge canary). The 3.22
base named here originally was dropped when the suite consolidated on 3.24.
- ✅ **22.10.1 (LTS)** on Alpine 3.24 - builds, signs, indexes; `asterisk -V` →
  `Asterisk 22.10.1`, 306 modules, `chan_pjsip` present, 19 subpackages.
- ✅ **23.4.1 (current)** on Alpine 3.24 - builds, signs, indexes; `asterisk -V` →
  `Asterisk 23.4.1`, 306 modules. Both versions coexist in one signed repo
  (`repository/v3.24/main/x86_64/`, 38 APKs total).
- **Findings (23.x):** `40-asterisk-cdefs.patch` had a second hunk for
  `utils/db1-ast/include/db.h` which Asterisk 23 removed; the 23.x patch keeps only the
  `main/ast_expr2.c` hunk. (This is the kind of per-line patch drift to expect.)
- ✅ **chan_sip policy - resolved** (verified 2026-07-22). Not a decision any more:
  Asterisk **21+ removed chan_sip from the source tree**, so it cannot be enabled on
  22/22-cert/23/git at all. It is **force-enabled on 20** (`--enable chan_sip`,
  `packages/20/APKBUILD:152`) and builds on every older line - `versions.mk` records
  "chan_sip works" for 1.6 and 1.8. pjsip-only is the present, not the future, from 22 up.
- Per-line `asterisk-opus` codec commit (`_opus_commit`) resolved - the traud/asterisk-opus
  fork is pinned to asterisk-13.7 historically; newer lines need the matching commit.
- Smoke tests (G5) wired per line.
- **Acceptance:** four modern repos build green, each runs `asterisk -V` and a SIP register
  test in CI.

### M3 - Repository consolidation & signing ✅
**Delivered via the Cloudsmith migration (2026-07), not the originally planned
self-hosted tree.** One signed repository (`asterisk/alpine`) serves every line
across `alpine/v3.24` + `alpine/edge`; Cloudsmith owns indexing and signing
(key `25B0C9A992BE0CEF`). Install instructions and a per-line pin guide are in
`README.md`; the acceptance test - a clean Alpine host installing any one line
from the public key plus one repo URL - was verified on 2026-07-22 for lines
from 1.6 through 23. Still open, folded into M6: populating `secfixes:` blocks.

- Unified index across all built lines; per-line `APKINDEX.tar.gz` signed with one key.
- Public key + install instructions per line; a top-level "choose your version" doc.
- `secfixes` blocks populated from the CVE history already in the 20.x APKBUILD, extended.
- Optional: a static `repo-server` (nginx) profile that serves the whole tree with a
  generated index page listing versions + EOL badges.
- **Acceptance:** a clean Alpine VM can `apk add` any one line using only the public key +
  one repo URL; versions never silently overlap.

### M4 - Walk into the past on Alpine 3.24 ✅
Attempted every line back to **1.6** on the single base. Kept the LTS + EOL-LTS
lines that build green: **20, 18, 16, 14, 1.8, 1.6**. Dropped the non-LTS
standard releases (17, 15, 13) - they added CI cost with no LTS payoff. The two
musl module-load fixes (recursive-mutex static init + dlclose loop) made even
**1.6** and **1.8** fully functional (all modules load).
- Each line: derive APKBUILD from the closest aports recipe (or the sibling project's
  Debian build), apply the musl patches that still match, run `abuild -r` on 3.24.
- Record outcome per line: `ok` (built + `asterisk -V` verified) or `fail:<root cause>`.
- The expected first failure is around **16/13** (OpenSSL 1.1-era upstream vs 3.0) and
  the ancient tier **11/10/1.8** (OpenSSL 1.0, glibc-only). Each failure is documented,
  not silently dropped - the failure frontier IS the deliverable for these lines.
- **Acceptance:** every row in the build list (§2) has a concrete `result`, green or red.

  Resurrect SHAs (aports) for the oldest lines, used to derive the recipe when needed:
  - 1.8.0 → `bd673b51a11a` (last 1.8.x packaged: 1.8.8.0_rc5)
  - 10.x → `6e8ed58d7cee` (10.9.0, last 10.x)
  - 11.x → `2.7-stable` branch (11.25.1) / `372b48e0f1c3` (11.11.1 on master)

### M5 - CI/CD + multi-arch ✅
**Delivered.** `ci.yml` runs the modern tier on every push/PR and the full tier
weekly (Mon) and on dispatch, with 1.6/1.8 gating each run; `build-edge.yml` is
the weekly Alpine-edge canary; `build-git-daily.yml` rebuilds the master
snapshot daily and skips when upstream is unchanged; `discover-releases.yml`
polls upstream and opens a version-bump PR against `buildchain/versions.mk` and
the APKBUILDs. Arch coverage: x86_64 + aarch64 natively, armv7 + armhf
(best-effort) for 22/23/22-cert. Publishing to Cloudsmith runs from the shared
`_publish.yml`, with the signing key supplied from CI secrets.

- GitHub Actions (or equivalent) matrix job: `{line} × {x86_64, aarch64}` via buildx/binfmt.
- Modern tier on every push; legacy/ancient on tag or manual dispatch (they're slow/fragile).
- Auto-publish repo artifacts; optional signing key from CI secrets.
- Upstream release poll → issue/PR to bump `versions.mk` (G6).

### M6 - Polish & docs ⬜
- README rewrite around the build list; per-line pages; version/EOL chooser in repo index.
- `secfixes`/CVE tracking automated from a feed; security badges.
- `make bump-<line> <ver>` helper; changelog generation.

---

## 5. Key design decisions (locked unless revisited)

1. **Single Alpine base (latest, 3.24) for every version.** The deliverable is the failure
   frontier - which versions survive OpenSSL 3 / musl / gcc 15 and which break. No
   period-appropriate bases; a line that won't build on 3.24 is recorded as a documented
   failure, not silently rescued. (Revised 2026-07-05 from an earlier multi-base matrix.)
2. **`pkgname=asterisk` everywhere; versions separated by repo path**, not by package name.
3. **chan_sip** is force-enabled on lines that still ship it (≤20); on 22+ it's gone from
   the source tree and cannot be re-enabled.
4. **Start from upstream aports APKBUILDs** (current + git-history resurrects) rather than
   hand-rolling - they already carry the musl patches and the subpackage splits we want.
5. **Ancient tier is explicitly best-effort.** Success is "we tried, here's what blocks us,"
   not a guarantee. No silent omission.
6. **Tiered CI:** modern on every push; legacy/ancient on demand. Keeps the feedback loop
   fast.

## 6. Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| pjproject fails to build on musl for a given line | Med | Start from aports recipe which already works; pin known-good pjproject; bundled mode as fallback. |
| Asterisk 1.8/10/11 won't compile on any available musl Alpine | High | Timebox; ship recipe + attempt log; consider glibc compat layer only if cheap. |
| chan_sip removal (22+) breaks user dialplans | Med | Force-enable chan_sip in menuselect (already done in 3.22 recipe). |
| `asterisk-opus` codec commit doesn't apply to a target line | Med | Per-line `_opus_commit`; drop `-opus` subpackage for lines where it won't apply rather than failing the build. |
| Subpackage set drift across eras (e.g. `-prometheus` only on 18+) | High | Per-line `subpackages=` in `versions.mk`; don't assume a fixed set. |
| Multi-arch doubles CI time | Med | Buildx caching; armv7 best-effort only. |

## 7. Sources

- Asterisk versions / EOL: https://docs.asterisk.org/About-the-Project/Asterisk-Versions/
- Asterisk releases: https://www.asterisk.org/downloads/asterisk/all-asterisk-versions/
- Alpine aports (canonical): https://gitlab.alpinelinux.org/alpine/aports · mirror https://github.com/alpinelinux/aports
- Alpine package index: https://pkgs.alpinelinux.org/packages?name=asterisk
- Bundled pjproject (since 13.8.0): https://docs.asterisk.org/Getting-Started/Installing-Asterisk/Installing-Asterisk-From-Source/Prerequisites/PJSIP-pjproject/
- OpenSSL 1.0 build break on 20+: https://github.com/asterisk/asterisk/issues/1892
- musl vs glibc differences: https://wiki.musl-libc.org/functional-differences-from-glibc.html
- Resurrect SHAs (aports git history): 1.8 `bd673b51a11a`, 10.x `6e8ed58d7cee`, 11.x `2.7-stable` / `372b48e0f1c3`, 22.x bump `0dec20c4fcb9`

## Multi-architecture coverage

Packages are published for four Alpine arches from one repository; apk resolves
the running arch automatically.

| Arch | Build | Lines | When |
|---|---|---|---|
| x86_64  | native (`ubuntu-latest`)     | all target lines | modern on PR/push, full on tag |
| aarch64 | native (`ubuntu-24.04-arm`)  | all target lines | modern on PR/push, full on tag |
| armv7   | QEMU (`linux/arm/v7`)        | 22, 23 (+22-cert best-effort) | full tier only, continue-on-error |
| armhf   | QEMU (`linux/arm/v6`)        | 22, 23 (+22-cert best-effort) | full tier only, continue-on-error |

Arch-independent packages (sample-config, doc, sounds, openrc) are published
once under a shared `v3.24/main/noarch/` tree referenced by every arch index.
See `docs/multi-arch-buildchain-design.md`.
