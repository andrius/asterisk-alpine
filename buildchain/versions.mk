# versions.mk - the Asterisk build list for the suite.
#
# STRATEGY: every Asterisk version builds on the current stable Alpine base
# (see buildchain/alpine-bases.env, sourced by ci.yml). When a new Alpine
# release ships it becomes STABLE and the prior one moves to PREVIOUS for an
# overlap window - both bases then build every line - until the old one is
# retired. The deliverable is the failure frontier: which versions survive the
# modern toolchain (OpenSSL 3, musl, gcc 15) and which break, with the break
# documented per line. No period-appropriate bases; old versions are attempted
# on the current base and recorded as build-or-break.
#
# The <alpine> column below is informational (the base a line was last verified
# on); the LIVE set of bases is alpine-bases.env, not this file.
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
22-cert  22.8-cert3          3.24   target   ok:pgsql,ldap,prometheus-subpkgs-omitted
22       22.10.1             3.24   target   ok
20       20.20.1             3.24   target   ok
18       18.26.4             3.24   target   ok:pgsql,ldap,prometheus-subpkgs-omitted
16       16.30.1             3.24   target   ok

# ---- dev: Asterisk master, snapshotted from git (pkgver + _gitrev set by
# ---- scripts/git-snapshot.sh; rebuild via 'make build-git') ----
git      24.0.0_git20260903  3.24   target   ok:master-snapshot-05033266

# ---- FAILURE FRONTIER ( pjproject ABI break on modern pjproject ) ----
14       14.7.8              3.24   target   ok:pj_in_addr+srtp-gcm-keysize-patches

# ---- ancient (now GREEN: recursive-mutex + dlclose patches fixed the musl module-load deadlock) ----
1.8      1.8.32.3            3.24   target   ok:185 modules load,chan_sip works (recursive mutex static init + dlclose loop fix)
1.6      1.6.2.24            3.24   target   ok:168 modules load,chan_sip works (recursive mutex static init + dlclose loop fix + bundled-AES stub)

# ---- ARCHITECTURE COVERAGE (see docs/multi-arch-buildchain-design.md) ----
# native  x86_64, aarch64 : every target line (modern on PR/push, full on tag)
# 32-bit  armv7,  armhf   : 22, 23 (targets) + 22-cert (best-effort), full tier
#                           only, continue-on-error. Line 20 is x86_64/aarch64.
#                           Ancient lines (1.6, 1.8) are x86_64 only - not
#                           validated on aarch64; built in CI on x86_64 (regular).
