#!/bin/sh
# notify-alpine-release.sh - open/close the GitHub "new Alpine release" issue.
#
# Called by discover-alpine.yml with the outputs of discover-alpine.sh:
#   args: <new> <stable> <newest>
#     new    - vX.Y if a new release was detected, else "" (empty)
#     stable - the pinned STABLE base (vX.Y)
#     newest - the newest upstream minor release (vX.Y)
#
# Behavior:
#   - new non-empty: open ONE issue titled "Alpine <new> released - migrate the
#     buildchain" (label alpine-bump), skipping if an open one already covers
#     <new>. Notifies the maintainer in person.
#   - new empty: auto-close any open alpine-bump issues (migration landed).
#
# --dry-run prints the gh write-commands instead of running them, so the script
# can be exercised locally without creating real issues (the read-only
# gh issue list calls still run, to exercise the decision logic).
#
# Requires gh in PATH and GH_TOKEN in env (the workflow passes GITHUB_TOKEN);
# gh infers the repo from the checkout cwd.
set -eu

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && { DRY_RUN=1; shift; }

NEW="${1:-}"
STABLE="${2:-}"
NEWEST="${3:-}"
PR_URL="${4:-}"   # optional: the draft PR opened by open-alpine-bump-pr.sh
RUN_URL="${5:-}"   # optional: the validation-build run URL
LABEL=alpine-bump

# Idempotent scoping-label creation (write - guarded by DRY_RUN).
if [ "$DRY_RUN" = 1 ]; then
  echo "+ gh label create $LABEL --color BFD4F2 --if-not-exists"
else
  gh label create "$LABEL" --color BFD4F2 --if-not-exists 2>/dev/null || true
fi

if [ -n "$NEW" ]; then
  # Notify once: if an open alpine-bump issue already covers this version, skip.
  # .[0] // empty: empty array indexes to null, which // drops to no output.
  existing=$(gh issue list --label "$LABEL" --state open \
    --json number,title \
    --jq "[.[] | select(.title | contains(\"$NEW\")) | .number] | .[0] // empty" \
    2>/dev/null || true)
  if [ -n "$existing" ]; then
    echo "Open $LABEL issue #$existing already covers $NEW - not duplicating."
    exit 0
  fi

  title="Alpine $NEW released - migrate the buildchain"
  body=$(cat <<EOF
A new stable Alpine release **$NEW** is available upstream; this suite pins **$STABLE**.

This issue is a heads-up only - the migration is a human job (the per-line musl/OpenSSL/gcc breakage a new base causes is not known until it builds):

1. **asterisk-alpine** (this repo): in buildchain/alpine-bases.env set STABLE=$NEW and PREVIOUS=$STABLE.
2. Build all lines on $NEW on a branch; fix breakage per the failure frontier.
3. Publish to the new Cloudsmith alpine/$NEW distribution. The consumer (andrius/asterisk) follows automatically via alpine-sync.yml.
4. Merge; retire PREVIOUS (empty it) when the old base is no longer needed.

Source: https://dl-cdn.alpinelinux.org/alpine/
Detected by the discover-alpine.yml workflow. This issue auto-closes once STABLE tracks $NEW.
EOF
)
  # Phase 2 links (present only when called from the propose job).
  if [ -n "$PR_URL" ]; then body="${body}

Draft PR (buildchain change): $PR_URL"; fi
  if [ -n "$RUN_URL" ]; then body="${body}

Validation build (modern tier on $NEW): $RUN_URL"; fi
  if [ "$DRY_RUN" = 1 ]; then
    echo "+ gh issue create --title \"$title\" --label $LABEL --body <<'BODY'"
    printf '%s\n' "$body"
    echo "BODY"
  else
    gh issue create --title "$title" --label "$LABEL" --body "$body"
  fi
else
  # STABLE tracks the newest release: auto-close any stale alpine-bump issues.
  count=$(gh issue list --label "$LABEL" --state open --json number --jq 'length' 2>/dev/null || echo 0)
  if [ "$count" = "0" ]; then
    echo "Nothing new (STABLE=$STABLE = upstream $NEWEST); no open issues to close."
    exit 0
  fi
  for n in $(gh issue list --label "$LABEL" --state open --json number --jq '.[].number'); do
    if [ "$DRY_RUN" = 1 ]; then
      echo "+ gh issue close $n --reason completed --comment \"...STABLE=$STABLE / newest=$NEWEST...\""
    else
      gh issue close "$n" --reason completed \
        --comment "Closing automatically: STABLE now tracks $STABLE (newest upstream $NEWEST). Migration complete."
    fi
  done
  echo "Closed $count stale $LABEL issue(s)."
fi
