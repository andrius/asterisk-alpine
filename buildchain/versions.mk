# versions.mk — the Asterisk build list for the suite.
#
# STRATEGY: ONE Alpine base (3.24, latest) for every Asterisk version. The
# deliverable is the failure frontier — which versions survive the modern
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
17       17.9.4              3.24   target   ok
16       16.30.1             3.24   target   ok
15       15.7.4              3.24   target   ok:cdefs-patch-trimmed,no-install-headers

# ---- FAILURE FRONTIER ( pjproject ABI break on modern pjproject ) ----
14       14.7.8              3.24   target   ok:pj_in_addr+srtp-gcm-keysize-patches
13       13.38.3             3.24   target   fail:db1-ast-HTAB-struct-mapp-removed (fails earlier than 14)

# ---- ancient (1.8 compiles but non-functional; 1.6 doesn't compile) ----
1.8      1.8.32.3            3.24   target   partial:builds+packages(10 APKs),asterisk-V works,modules fail to load (symbol relocation)
1.6      1.6.2.24            3.24   target   fail:aesopt.h non-constant initializers (bundled AES crypto tables, deep C-standards drift)
