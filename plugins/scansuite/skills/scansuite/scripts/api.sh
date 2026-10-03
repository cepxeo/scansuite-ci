#!/usr/bin/env bash
#
# api.sh — one call to the ScanSuite team API, with the token read from a file.
#
#   bash api.sh GET /context
#   bash api.sh GET "/scans?product_id=8&limit=5"
#   bash api.sh POST /products '{"product_name":"shop"}'
#   bash api.sh -o report.zip GET /scans/123/report
#
# PATH is relative to $SCANSUITE_URL/api/teams/$SCANSUITE_TEAM. The answer goes to
# stdout (or to the -o file); an HTTP error status exits 1 with the status on
# stderr. The token reaches curl as a config line on stdin, so it never appears
# on a command line or in a file.
set -euo pipefail

: "${SCANSUITE_URL:?Set SCANSUITE_URL}"
: "${SCANSUITE_TEAM:?Set SCANSUITE_TEAM}"
token_file="${SCANSUITE_TOKEN_FILE:-$HOME/.scansuite-token}"
[ -r "$token_file" ] || { echo "No readable token file at $token_file" >&2; exit 3; }

output=""
if [ "${1:-}" = "-o" ]; then
    output="$2"
    shift 2
fi
[ $# -ge 2 ] || { echo "usage: api.sh [-o FILE] METHOD PATH [JSON]" >&2; exit 2; }
method="$1" path="$2" body="${3:-}"

args=(-sS --config - -X "$method")
if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" --data "$body")
fi
url="$SCANSUITE_URL/api/teams/$SCANSUITE_TEAM$path"
auth() { printf 'header = "Authorization: Bearer %s"\n' "$(tr -d '\r\n' < "$token_file")"; }

if [ -n "$output" ]; then
    status="$(auth | curl "${args[@]}" -o "$output" -w '%{http_code}' "$url")"
else
    response="$(auth | curl "${args[@]}" -w $'\n%{http_code}' "$url")"
    status="${response##*$'\n'}"
    printf '%s\n' "${response%$'\n'*}"
fi
if [ "$status" -ge 400 ]; then
    echo "HTTP $status from $method $path" >&2
    exit 1
fi
