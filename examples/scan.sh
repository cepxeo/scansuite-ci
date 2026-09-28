#!/usr/bin/env bash
#
# scan.sh — run a ScanSuite scan via the scansuite-ci container and gate the build.
#
# A reusable wrapper: configure it with environment variables and pass any extra
# client flags as arguments. Drop it in your repo and call it from any CI system.
#
#   Required (SCANSUITE_TOKEN must be a masked CI secret — it is never printed):
#     SCANSUITE_URL       e.g. https://scansuite.example.com
#     SCANSUITE_TEAM      your team slug, e.g. appsec
#     SCANSUITE_TOKEN     a service-account API token
#     SCANSUITE_PRODUCT   the product name  (or pass --product-id N as an argument)
#
#   Optional:
#     SCANSUITE_IMAGE     image to run       (default: appsec4u/scansuite-ci:1)
#     SCANSUITE_PROFILE   quick|standard|deep (default: standard)
#
#   Examples:
#     ./scan.sh
#     ./scan.sh --changed-only --base origin/main
#     SCANSUITE_PROFILE=quick ./scan.sh --changed-only
#     SCANSUITE_PROFILE=deep  ./scan.sh --report-zip scansuite-report.zip
#     ./scan.sh --scanners mlsast --options mlsast_reachability --min-confidence reachable
#
# Exit code is the client's: 0 pass · 1 gate failed · 2 scan failed · 3 config
# · 4 timeout · 5 server unreachable.

set -uo pipefail

IMAGE="${SCANSUITE_IMAGE:-appsec4u/scansuite-ci:1}"
PROFILE="${SCANSUITE_PROFILE:-standard}"

# --- prerequisites ---------------------------------------------------------
command -v docker >/dev/null 2>&1 || { echo "error: docker is required" >&2; exit 3; }

missing=""
for v in SCANSUITE_URL SCANSUITE_TEAM SCANSUITE_TOKEN; do
  [ -n "${!v:-}" ] || missing="$missing $v"
done
if [ -n "$missing" ]; then
  echo "error: set these environment variables first:$missing" >&2
  echo "       (SCANSUITE_TOKEN must be a masked CI secret)" >&2
  exit 3
fi

# --- run -------------------------------------------------------------------
# The checkout is mounted at /src; the token is forwarded as an env var only.
docker run --rm -v "$PWD:/src" -w /src \
  -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
  -e SCANSUITE_PRODUCT -e SCANSUITE_PRODUCT_ID \
  "$IMAGE" \
  --profile "$PROFILE" \
  --junit scansuite-junit.xml --summary-json scansuite.json --sarif scansuite.sarif \
  "$@"
code=$?

# --- explain the result ----------------------------------------------------
case "$code" in
  0) echo "ScanSuite: gate passed (or nothing to scan)";;
  1) echo "ScanSuite: quality gate FAILED — blocking findings/secrets above" >&2;;
  2) echo "ScanSuite: the scan failed, was cancelled, or was refused" >&2;;
  3) echo "ScanSuite: configuration error (bad option, token, permission, or TLS)" >&2;;
  4) echo "ScanSuite: timed out waiting for the scan" >&2;;
  5) echo "ScanSuite: the server was unreachable or returned an error" >&2;;
  *) echo "ScanSuite: exited $code" >&2;;
esac
exit "$code"
