#!/bin/sh
# git-snapshot.sh - pin Asterisk master to a commit + version in packages/git/APKBUILD.
#
# Run before abuild (via 'make build-git'). Resolves master HEAD to a SHA and
# rewrites _gitrev/pkgver in the APKBUILD. The base version is the NEXT_MAJOR
# constant below (master's AC_INIT is literally "[master]", not a number).
# abuild then fetches the GitHub archive for that exact commit.
#
# Usage: git-snapshot.sh <APKBUILD-path>
set -eu

APKBUILD="${1:-packages/git/APKBUILD}"
REPO="https://github.com/asterisk/asterisk.git"

# master's AC_INIT is literally "[master]" (numeric versions only land on
# release branches), so the base is the next major after the current Standard
# line. Bump this when Asterisk releases 24 and master moves to 25.
NEXT_MAJOR="24.0.0"

if [ ! -f "$APKBUILD" ]; then
	echo "ERROR: APKBUILD not found: $APKBUILD" >&2
	exit 1
fi

if ! command -v git >/dev/null; then
	echo "ERROR: git is required" >&2
	exit 1
fi

# 1. Resolve master HEAD to a full commit SHA.
SHA="$(git ls-remote "$REPO" refs/heads/master | awk '{print $1}')"
if [ -z "$SHA" ]; then
	echo "ERROR: could not resolve master HEAD from $REPO" >&2
	exit 1
fi
echo "master HEAD: $SHA"

# 2. Base version: master carries no numeric version, so use NEXT_MAJOR.
BASE="$NEXT_MAJOR"
echo "base version: $BASE"

# 3. pkgver = <base>_git<YYYYMMDD>. The _git suffix sorts after the base so a
#    later real release of the same base still wins.
DATE="$(date -u +%Y%m%d)"
PKGVER="${BASE}_git${DATE}"
echo "pkgver: $PKGVER"

# 4. Rewrite _gitrev + pkgver in the APKBUILD (idempotent, plain-line replace).
sed -i "s|^_gitrev=.*|_gitrev=$SHA|" "$APKBUILD"
sed -i "s|^pkgver=.*|pkgver=$PKGVER|" "$APKBUILD"

echo "snapshot pinned: $SHA, pkgver=$PKGVER (in $APKBUILD)"
