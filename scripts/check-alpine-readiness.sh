#!/bin/sh
# check-alpine-readiness.sh - are the build and publish prerequisites of a
# newly detected Alpine release in place yet?
#
# Arg: <version> - the Alpine version, v-prefixed (v3.25) or bare (3.25).
#
# A detected release is only actionable when BOTH hold:
#   1. docker.io/library/alpine:<version> exists - every builder container and
#      the smoke-test container are FROM it (docker/builder.Dockerfile,
#      docker/test.Dockerfile);
#   2. Cloudsmith offers the alpine/v<version> distribution - the publish
#      target of the migration (_publish.yml: dist="alpine/$ALPINE_VERSION").
# Until then the validate legs cannot build (missing image) and/or a merged
# bump could not publish (missing distribution), so discover-alpine gates the
# validate legs on these outputs and the issue lists what is being waited on.
#
# Outputs (GITHUB_OUTPUT + stdout):
#   docker_ready=true|false
#   cloudsmith_ready=true|false
#   waiting=<missing prerequisites as a human list; empty when both ready>
#
# Exit 0 even when not ready (readiness is data, not a failure). A probe that
# cannot run emits ::warning:: and reports that leg as not ready, so a
# transient API outage delays validation by a day instead of failing the run.
#
# --dry-run prints the probes instead of running them.
# Cloudsmith probe needs CLOUDSMITH_API_KEY in env (the workflow passes the
# repo secret of the same name).
set -eu

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && { DRY_RUN=1; shift; }
VERSION="${1:?usage: check-alpine-readiness.sh <version>}"
VERSION=${VERSION#v}
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

# --- 1. Docker Hub: does the builder/smoke base tag exist? -------------------
hub_code=$(curl -s -o /dev/null -w '%{http_code}' --retry 2 \
  "https://registry.hub.docker.com/v2/repositories/library/alpine/tags/$VERSION")
case "$hub_code" in
  200) docker_ready=true ;;
  404) docker_ready=false ;;
  *)   echo "::warning::Docker Hub tag probe returned HTTP $hub_code (expected 200/404)"
       docker_ready=false ;;
esac
echo "docker.io/library/alpine:$VERSION -> HTTP $hub_code (ready: $docker_ready)"

# --- 2. Cloudsmith: does the alpine/v<version> distribution exist? -----------
# The distros listing names every distribution version they can index; the
# publish path maps ALPINE_VERSION to it 1:1, so the exact slug must be there.
cloudsmith_ready=false
if [ "$DRY_RUN" = 1 ]; then
  echo "+ curl -H 'X-Api-Key: …' https://api.cloudsmith.io/v1/distros/ | jq 'alpine versions'"
elif [ -z "${CLOUDSMITH_API_KEY:-}" ]; then
  echo "::warning::CLOUDSMITH_API_KEY not set - cannot probe Cloudsmith distributions"
else
  if curl -fsSL --retry 2 -H "X-Api-Key: $CLOUDSMITH_API_KEY" \
      https://api.cloudsmith.io/v1/distros/ 2>/dev/null \
      | jq -e --arg v "v$VERSION" \
        'map(select(.slug == "alpine")) | .[0].versions | any(.slug == $v)' \
      | grep -q true; then
    cloudsmith_ready=true
  fi
fi
echo "cloudsmith alpine/v$VERSION distribution -> ready: $cloudsmith_ready"

# --- Waiting list (drives the issue text and the validate gate) ---------------
WAITING=""
[ "$docker_ready" = true ]    || WAITING="docker image alpine:$VERSION on Docker Hub"
[ "$cloudsmith_ready" = true ] || WAITING="${WAITING:+$WAITING; }alpine/v$VERSION distribution on Cloudsmith"
[ -n "$WAITING" ] && echo "::notice::not actionable yet - waiting on: $WAITING"

{
  echo "docker_ready=$docker_ready"
  echo "cloudsmith_ready=$cloudsmith_ready"
  echo "waiting=$WAITING"
} >> "$GITHUB_OUTPUT"
