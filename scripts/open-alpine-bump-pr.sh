#!/bin/sh
# open-alpine-bump-pr.sh - open/refresh a DRAFT PR migrating the buildchain to
# a newly-detected Alpine release (Phase 2, Option A).
#
# Args: <new> <stable>
#   new    - vX.Y, the newly detected release (becomes STABLE)
#   stable - vX.Y, the current STABLE (becomes PREVIOUS for the overlap window)
#
# Edits buildchain/alpine-bases.env (STABLE=<new>, PREVIOUS=<stable>), commits
# to branch alpine-bump-<new>, force-pushes, and opens a DRAFT PR if one does
# not already exist for that branch. The PR is informational: the validation
# build already ran in the discover-alpine workflow, so this PR is NOT expected
# to re-run CI (a GITHUB_TOKEN-opened PR cannot trigger ci.yml anyway).
#
# Idempotent: re-running with the same <new> refreshes the branch in place and
# leaves any existing draft PR alone. Outputs pr_url=<url> to GITHUB_OUTPUT.
#
# --dry-run prints the actions (without mutating the file or the repo).
# Requires gh in PATH and GH_TOKEN in env for the real path.
set -eu

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && { DRY_RUN=1; shift; }

NEW="${1:?usage: open-alpine-bump-pr.sh <new> <stable>}"
STABLE="${2:?usage: open-alpine-bump-pr.sh <new> <stable>}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"
BRANCH="alpine-bump-${NEW}"

if [ "$DRY_RUN" = 1 ]; then
  echo "+ sed -i \"s|^STABLE=.*|STABLE=$NEW|\" buildchain/alpine-bases.env"
  echo "+ sed -i \"s|^PREVIOUS=.*|PREVIOUS=$STABLE|\" buildchain/alpine-bases.env"
  echo "+ git checkout -B $BRANCH"
  echo "+ git commit buildchain/alpine-bases.env"
  echo "+ git push --force-with-lease origin $BRANCH"
  echo "+ gh pr create --draft --base main --head $BRANCH --title \"Alpine $NEW: migrate buildchain (draft)\""
  exit 0
fi

# Edit the single source of truth.
sed -i "s|^STABLE=.*|STABLE=$NEW|" buildchain/alpine-bases.env
sed -i "s|^PREVIOUS=.*|PREVIOUS=$STABLE|" buildchain/alpine-bases.env
echo "buildchain/alpine-bases.env -> $(grep -E '^(STABLE|PREVIOUS)=' buildchain/alpine-bases.env | tr '\n' ' ')"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -B "$BRANCH"
git add buildchain/alpine-bases.env
if git diff --cached --quiet; then
  echo "No change ($BRANCH already carries this edit)."
else
  git commit -m "Alpine $NEW: set STABLE=$NEW, PREVIOUS=$STABLE (auto-detected)"
fi
git push --force-with-lease origin "$BRANCH"

# Reuse an existing draft PR for this branch if present; otherwise open one.
existing=$(gh pr list --head "$BRANCH" --state open --json url --jq '.[0].url // empty' 2>/dev/null || true)
if [ -n "$existing" ]; then
  echo "Draft PR already open: $existing"
  echo "pr_url=$existing" >> "$GITHUB_OUTPUT"
  exit 0
fi

title="Alpine $NEW: migrate buildchain (draft)"
body=$(cat <<EOF
Auto-generated DRAFT PR from the discover-alpine.yml workflow.

Alpine $NEW was detected upstream; this sets STABLE=$NEW and PREVIOUS=$STABLE in buildchain/alpine-bases.env.

DRAFT - do not merge until the failure frontier is reviewed. The validation build (modern tier on $NEW) ran in the detect workflow; the linked issue and run show which lines built and which broke. Fix the per-line musl/OpenSSL/gcc breakage here, then promote out of draft.

Merging makes the suite build + publish on $NEW while keeping $STABLE during the overlap window. The consumer (andrius/asterisk) follows automatically via alpine-sync.yml.
EOF
)
pr_url=$(gh pr create --draft --base main --head "$BRANCH" --title "$title" --body "$body")
echo "pr_url=$pr_url" >> "$GITHUB_OUTPUT"
echo "Opened draft PR: $pr_url"
