#!/usr/bin/env bash
#
# ai-sast-pr.sh — AI static analysis on just the files a pull/merge request changes,
# blocking only on findings the AI confirms are reachable. Fast enough for every PR.
#
#   Required (SCANSUITE_TOKEN must be a masked CI secret):
#     SCANSUITE_URL, SCANSUITE_TEAM, SCANSUITE_TOKEN, SCANSUITE_PRODUCT
#
#   Base branch to diff against (first argument, or $BASE, default origin/main):
#     ./ai-sast-pr.sh                    # diff against origin/main
#     ./ai-sast-pr.sh origin/develop     # diff against another base
#
# Check out full history (git fetch --unshallow / fetch-depth: 0) so the merge base
# can be found; the client fetches the base branch itself if a shallow clone lacks it.

set -uo pipefail

IMAGE="${SCANSUITE_IMAGE:-appsec4u/scansuite-ci:1}"
BASE="${1:-${BASE:-origin/main}}"

command -v docker >/dev/null 2>&1 || { echo "error: docker is required" >&2; exit 3; }
for v in SCANSUITE_URL SCANSUITE_TEAM SCANSUITE_TOKEN SCANSUITE_PRODUCT; do
  [ -n "${!v:-}" ] || { echo "error: set $v (SCANSUITE_TOKEN must be a masked secret)" >&2; exit 3; }
done

echo "AI SAST on files changed since $BASE ..."
docker run --rm -v "$PWD:/src" -w /src \
  -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
  "$IMAGE" \
  --scanners mlsast --options mlsast_reachability \
  --changed-only --base "$BASE" \
  --min-confidence reachable --fail-on-severity high \
  --sarif scansuite.sarif --junit scansuite-junit.xml
code=$?

[ "$code" -eq 0 ] && echo "AI SAST: no reachable High/Critical in the changed files" \
                  || echo "AI SAST: exit $code (see findings above)" >&2
exit "$code"
