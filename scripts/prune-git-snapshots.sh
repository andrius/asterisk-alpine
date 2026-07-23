#!/bin/sh
# Prune superseded Asterisk "git" (master snapshot) packages from one Cloudsmith
# Alpine distribution, keeping the newest $KEEP snapshot(s).
#
# WHY THIS EXISTS
#   The git line is rebuilt on every master change (daily on v3.24, weekly on
#   edge) and each build publishes a fresh 24.0.0_git<YYYYMMDD> version. Nothing
#   removed the previous one - Cloudsmith retention rules are a paid feature not
#   available on the Open-Source plan (the API returns 402), and the "publish
#   prunes older _git snapshots" note in the workflows described the retired
#   GitHub Pages flow, where republishing the index dropped old snapshots. So
#   git snapshots accumulated ~31 packages per build, unbounded. This script is
#   the missing prune.
#
# SAFETY
#   - Only versions whose string contains "_git" are ever eligible. Release
#     lines (1.6 .. 23, 22-cert) are never matched, so they cannot be deleted.
#   - Scoped to a SINGLE distribution ($ALPINE_VERSION). The same git version
#     can be the newest in one distribution and superseded in another (edge and
#     v3.24 move on different cadences), so pruning by version string across the
#     whole repo would delete a live package. Per-distribution scoping is
#     mandatory, not an optimisation.
#   - Keeps the newest $KEEP snapshot(s) by apk version order.
#   - PRUNE_DRY_RUN=1 lists what would be deleted and deletes nothing.
#
# ENV
#   CLOUDSMITH_API_KEY  (required)
#   CLOUDSMITH_OWNER    default: asterisk
#   CLOUDSMITH_REPO     default: alpine
#   ALPINE_VERSION      distribution slug: v3.24 | edge (required)
#   KEEP                snapshots to keep, newest-first (default: 1)
#   PRUNE_DRY_RUN       1 = report only (default: 0)
set -eu

: "${CLOUDSMITH_API_KEY:?CLOUDSMITH_API_KEY must be set}"
OWNER="${CLOUDSMITH_OWNER:-asterisk}"
REPO="${CLOUDSMITH_REPO:-alpine}"
DIST="${ALPINE_VERSION:?ALPINE_VERSION (distribution slug) must be set}"
KEEP="${KEEP:-1}"
DRY="${PRUNE_DRY_RUN:-0}"
API="https://api.cloudsmith.io/v1"

echo "prune-git-snapshots: repo=$OWNER/$REPO dist=$DIST keep=$KEEP dry_run=$DRY"

# Fetch every package (paged), then let python do the filtering + selection so
# the version ordering and per-distribution scoping live in one place.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
page=1
: > "$tmp/all.ndjson"
while [ "$page" -le 60 ]; do
  code=$(curl -sS -o "$tmp/p.json" -w '%{http_code}' \
      -H "X-Api-Key: $CLOUDSMITH_API_KEY" \
      "$API/packages/$OWNER/$REPO/?page=$page&page_size=250")
  # Cloudsmith returns 404 for any page past the last one - that is the normal
  # end-of-pagination signal here, not an error.
  [ "$code" = "404" ] && break
  [ "$code" = "200" ] || { echo "::error::Cloudsmith list HTTP $code on page $page"; exit 1; }
  n=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d))' "$tmp/p.json")
  [ "$n" -gt 0 ] || break
  python3 -c 'import json,sys
for p in json.load(open(sys.argv[1])): print(json.dumps(p))' "$tmp/p.json" >> "$tmp/all.ndjson"
  page=$((page + 1))
done

# Select identifiers to delete: git versions in THIS distribution, minus the
# newest KEEP. Version order sorts 24.0.0_git20260716 < ..0720 < ..0722. The
# human summary goes to stderr; the tab-separated delete list is the only thing
# on stdout, so it is what gets captured into delete.tsv.
python3 - "$tmp/all.ndjson" "$DIST" "$KEEP" > "$tmp/delete.tsv" <<'PY'
import json,re,sys
path,dist,keep=sys.argv[1],sys.argv[2],int(sys.argv[3])
def vkey(v):
    return [int(x) if x.isdigit() else x for x in re.split(r'[._\-r]+', v) if x!='']
rows=[json.loads(l) for l in open(path) if l.strip()]
git=[p for p in rows
     if "_git" in (p.get("version") or "")
     and ((p.get("distro_version") or {}).get("slug")==dist)]
versions=sorted({p["version"] for p in git}, key=vkey)
keepset=set(versions[-keep:]) if keep>0 else set()
print(f"  git versions in {dist}: {versions or '(none)'}", file=sys.stderr)
print(f"  keeping newest {keep}: {sorted(keepset) or '(none)'}", file=sys.stderr)
for p in git:
    if p["version"] not in keepset:
        print(f'{p["identifier_perm"]}\t{p["version"]}\t{p.get("filename","")}')
PY

count=$(wc -l < "$tmp/delete.tsv" | tr -d ' ')
if [ "$count" -eq 0 ]; then
  echo "nothing to prune in $DIST"
  exit 0
fi
echo "will prune $count package(s) from $DIST:"
sort -k2 "$tmp/delete.tsv" | awk -F'\t' '{printf "    %-14s %s\n",$2,$3}'

if [ "$DRY" = "1" ]; then
  echo "PRUNE_DRY_RUN=1 - no deletions performed"
  exit 0
fi

deleted=0
while IFS="$(printf '\t')" read -r ident version filename; do
  [ -n "$ident" ] || continue
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
      -H "X-Api-Key: $CLOUDSMITH_API_KEY" \
      "$API/packages/$OWNER/$REPO/$ident/")
  case "$code" in
    204|200) deleted=$((deleted + 1)); echo "  deleted $version $filename" ;;
    404)     echo "  already gone: $version $filename" ;;
    *)       echo "::error::DELETE $ident ($version $filename) -> HTTP $code"; exit 1 ;;
  esac
done < "$tmp/delete.tsv"
echo "pruned $deleted package(s) from $DIST"
