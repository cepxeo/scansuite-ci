#!/usr/bin/env bash
#
# ai-deep-nightly.sh — a full AI scan of the whole repository, for a nightly schedule.
# Runs AI static analysis (reachability, security architecture, cross-file boundary
# hunt), AI dependency checks (reachability) and AI-verified secret scanning, with a
# per-severity budget, and saves the report. Slower and higher AI cost — not for PRs.
#
#   Required (SCANSUITE_TOKEN must be a masked CI secret):
#     SCANSUITE_URL, SCANSUITE_TEAM, SCANSUITE_TOKEN, SCANSUITE_PRODUCT
#
#   The secrets gate (--fail-on-secrets all) needs the credential.read permission on
#   the token. Without it, replace "all" with "none" and drop "secrets" / "secrets_ai".
#
#   Cron example (2 a.m. daily):
#     0 2 * * *  cd /path/to/repo && ./examples/ai-deep-nightly.sh >> scansuite.log 2>&1

set -uo pipefail

IMAGE="${SCANSUITE_IMAGE:-appsec4u/scansuite-ci:1}"

command -v docker >/dev/null 2>&1 || { echo "error: docker is required" >&2; exit 3; }
for v in SCANSUITE_URL SCANSUITE_TEAM SCANSUITE_TOKEN SCANSUITE_PRODUCT; do
  [ -n "${!v:-}" ] || { echo "error: set $v (SCANSUITE_TOKEN must be a masked secret)" >&2; exit 3; }
done

echo "Deep AI scan (SAST + dependencies + secrets) starting ..."
docker run --rm -v "$PWD:/src" -w /src \
  -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
  "$IMAGE" \
  --scanners mlsast,dep_checks,secrets \
  --options mlsast_reachability,mlsast_security_architecture,mlsast_boundary_hunt,dep_checks_ai,dep_checks_reachability,secrets_ai \
  --max high=0,critical=0,medium=10 \
  --fail-on-secrets all \
  --timeout 14400 \
  --summary-json scansuite.json --report-zip scansuite-report.zip
code=$?

[ "$code" -eq 0 ] && echo "Deep AI scan: within budget, report saved to scansuite-report.zip" \
                  || echo "Deep AI scan: exit $code (report saved to scansuite-report.zip)" >&2
exit "$code"
