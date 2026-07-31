#!/bin/sh
# discover-alpine.sh - detect a stable Alpine release newer than the pinned
# STABLE in buildchain/alpine-bases.env, by listing dl-cdn.alpinelinux.org.
#
# The Alpine mirror root is an autoindex of release trees: v3.20/, v3.21/,
# ... v3.24/, plus edge/ and a latest-stable/ symlink. A new MINOR release
# (e.g. v3.25) appears there as a new vX.Y/ dir on release day - before it
# surfaces in any more structured feed - so scraping the index is the most
# reliable signal. Point releases (3.24.1, 3.24.2) live INSIDE a vX.Y tree
# and are intentionally NOT detected here: they roll out via the weekly base-
# image rebuild, not a buildchain migration.
#
# Outputs (GITHUB_OUTPUT + stdout):
#   stable=<vX.Y>   the currently pinned STABLE base
#   newest=<vX.Y>   the newest minor release available upstream
#   new=<vX.Y|>     the newest release if it is newer than STABLE, else empty
#
# Exit 0 on success (the caller reads $new); exit 1 only if the index is
# unreachable or unparseable, so the caller can skip the notify step.
set -eu

. ./buildchain/alpine-bases.env
[ -n "$STABLE" ] || { echo "::error::STABLE not set in alpine-bases.env"; exit 1; }

# Default so the script runs standalone (local testing); CI sets this for real.
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

INDEX=$(curl -fsSL --retry 2 https://dl-cdn.alpinelinux.org/alpine/ 2>/dev/null || true)

# Stable release trees are href="vX.Y/" in the autoindex. Drop edge/ and the
# latest-stable/ symlink (it resolves to a vX.Y already in the list). The
# trailing-slash anchor avoids matching anything inside a release tree.
newest=$(printf '%s\n' "$INDEX" \
  | grep -oE 'href="v[0-9]+\.[0-9]+/"' \
  | sed -E 's|href="v([0-9]+\.[0-9]+)/"|\1|' \
  | sort -V -u | tail -1)

[ -n "$newest" ] || { echo "::error::could not parse any vX.Y release from dl-cdn index"; exit 1; }

cur=${STABLE#v}   # v3.24 -> 3.24
echo "STABLE=$STABLE (= $cur); newest upstream minor release = $newest"

# new = newest only when strictly greater than the pinned STABLE.
new=""
if [ "$newest" != "$cur" ] \
   && [ "$(printf '%s\n%s\n' "$cur" "$newest" | sort -V | tail -1)" = "$newest" ]; then
  new="v$newest"
  echo "::notice::new Alpine minor release detected: v$newest (pinned STABLE=$STABLE)"
fi

{
  echo "stable=$STABLE"
  echo "newest=v$newest"
  echo "new=$new"
} >> "$GITHUB_OUTPUT"
