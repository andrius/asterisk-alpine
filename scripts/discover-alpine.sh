#!/bin/sh
# discover-alpine.sh - detect a stable Alpine release newer than the pinned
# STABLE in buildchain/alpine-bases.env, by asking dl-cdn.alpinelinux.org
# what ITS OWN latest-stable pointer serves.
#
# The mirror root autoindexes release trees (v3.20/, ..., edge/), and a new
# MINOR's staging tree appears there WEEKS before release: v3.25/ (packages
# synced from edge, zero ISOs in releases/) sat in the index from 2026-11-09
# while alpinelinux.org/releases still listed v3.24 as newest - scraping the
# index produced a 9-day false "new release" (PR #57, issue #59). The CDN's
# latest-stable symlink flips to the new tree on release day, and the
# latest-releases.yaml it serves names its branch - that is the release
# signal. Point releases (3.24.1, 3.24.2) live INSIDE a vX.Y tree and are
# intentionally NOT detected here: they roll out via the weekly base-image
# rebuild, not a buildchain migration.
#
# Outputs (GITHUB_OUTPUT + stdout):
#   stable=<vX.Y>   the currently pinned STABLE base
#   newest=<vX.Y>   the newest stable minor release upstream
#   new=<vX.Y|>     the newest release if it is newer than STABLE, else empty
#
# Exit 0 on success (the caller reads $new); exit 1 only if the YAML is
# unreachable or unparseable, so the caller can skip the notify step.
set -eu

. ./buildchain/alpine-bases.env
[ -n "$STABLE" ] || { echo "::error::STABLE not set in alpine-bases.env"; exit 1; }

# Default so the script runs standalone (local testing); CI sets this for real.
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

YAML=$(curl -fsSL --retry 2 \
  https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml \
  2>/dev/null || true)

# Every artifact entry in the YAML carries the same "branch: vX.Y"; take the
# first. An unreachable/empty fetch leaves newest empty and fails below.
newest=$(printf '%s\n' "$YAML" | sed -n 's/^[[:space:]]*branch:[[:space:]]*v\([0-9]*\.[0-9]*\)[[:space:]]*$/\1/p' | head -1)

[ -n "$newest" ] || { echo "::error::could not parse a branch from latest-stable latest-releases.yaml"; exit 1; }

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
