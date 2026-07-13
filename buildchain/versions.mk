# versions.mk - the Asterisk build list for the suite.
#
# STRATEGY: ONE Alpine base (3.24, latest) for every Asterisk version. The
# deliverable is the failure frontier - which versions survive the modern
# toolchain (OpenSSL 3, musl, gcc 15) and which break, with the break
# documented per line. No period-appropriate bases; old versions are attempted
# on 3.24 and recorded as build-or-break.
#
# Format (space-separated, comments start with #):
#   <line>   <asterisk_ver>      <alpine>  <status>   <result>
#
# status: target (we want it) | skip
# result: ok | fail:<reason> | tbd
#
# Reference date: 2026-07-05. See ROADMAP.md.

# ---- BUILT GREEN on Alpine 3.24 (verified: asterisk -V) ----
23       23.4.1              3.24   target   ok
22-cert  22.8-cert3          3.24   target   ok:pgsql,ldap,tds,prometheus-subpkgs-omitted
22       22.10.1             3.24   target   ok
20       20.20.1             3.24   target   ok
18       18.26.4             3.24   target   ok:pgsql,ldap,prometheus-subpkgs-omitted
16       16.30.1             3.24   target   ok

# ---- dev: Asterisk master, snapshotted from git (pkgver + _gitrev set by
# ---- scripts/git-snapshot.sh; rebuild via 'make build-git') ----
git      24.0.0_git20260713  3.24   target   ok:master-snapshot-ae85ad74

# ---- FAILURE FRONTIER ( pjproject ABI break on modern pjproject ) ----
14       14.7.8              3.24   target   ok:pj_in_addr+srtp-gcm-keysize-patches

# ---- ancient (now GREEN: recursive-mutex + dlclose patches fixed the musl module-load deadlock) ----
1.8      1.8.32.3            3.24   target   ok:185 modules load,chan_sip works (recursive mutex static init + dlclose loop fix)
1.6      1.6.2.24            3.24   target   ok:168 modules load,chan_sip works (recursive mutex static init + dlclose loop fix + bundled-AES stub)

# ---- ARCHITECTURE COVERAGE (see docs/multi-arch-buildchain-design.md) ----
# native  x86_64, aarch64 : every target line (modern on PR/push, full on tag)
# 32-bit  armv7,  armhf   : 22, 23 (targets) + 22-cert (best-effort), full tier
#                           only, continue-on-error. Line 20 and ancient lines
#                           are x86_64/aarch64 only.
