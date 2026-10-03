#!/usr/bin/env bash
#
# ssci.sh — run the ScanSuite CI client with the token read from a file.
#
#   SCANSUITE_URL=https://scansuite.example.com SCANSUITE_TEAM=appsec \
#       bash ssci.sh --product-name my-app --profile standard-ai --summary-json scan.json
#
# Every argument goes to scansuite-ci. The token comes from SCANSUITE_TOKEN_FILE
# (default ~/.scansuite-token) through --token-file, so it is never on a command
# line or in the environment of the container.
#
# How the client runs, in this order:
#   SCANSUITE_CLIENT=/path/scansuite-ci.py   that script, with python3
#   docker available (and not                 the image (SCANSUITE_IMAGE, default
#   SCANSUITE_USE_DOCKER=0)
#                                             appsec4u/scansuite-ci:1), the current
#                                             directory mounted at /src
#   otherwise                                 the client the server serves, cached
#                                             and checked against its SHA-256
set -euo pipefail

: "${SCANSUITE_URL:?Set SCANSUITE_URL, e.g. https://scansuite.example.com}"
: "${SCANSUITE_TEAM:?Set SCANSUITE_TEAM to the team slug}"
token_file="${SCANSUITE_TOKEN_FILE:-$HOME/.scansuite-token}"
if [ ! -r "$token_file" ]; then
    echo "No readable token file at $token_file; create it (chmod 600) or set SCANSUITE_TOKEN_FILE" >&2
    exit 3
fi
export SCANSUITE_URL SCANSUITE_TEAM

if [ -n "${SCANSUITE_CLIENT:-}" ]; then
    exec python3 "$SCANSUITE_CLIENT" --token-file "$token_file" "$@"
fi

if [ "${SCANSUITE_USE_DOCKER:-1}" != 0 ] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    exec docker run --rm -v "$PWD:/src" -w /src -v "$token_file:/run/scansuite-token:ro" \
        -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_PRODUCT -e SCANSUITE_PRODUCT_ID \
        "${SCANSUITE_IMAGE:-appsec4u/scansuite-ci:1}" --token-file /run/scansuite-token "$@"
fi

cache="${XDG_CACHE_HOME:-$HOME/.cache}/scansuite"
mkdir -p "$cache"
expected="$(curl -fsS "$SCANSUITE_URL/ci/scansuite-ci.py.sha256" | awk '{print $1}')"
if [ ! -f "$cache/scansuite-ci.py" ] || [ "$(sha256sum "$cache/scansuite-ci.py" | awk '{print $1}')" != "$expected" ]; then
    curl -fsS -o "$cache/scansuite-ci.py.new" "$SCANSUITE_URL/ci/scansuite-ci.py"
    actual="$(sha256sum "$cache/scansuite-ci.py.new" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        rm -f "$cache/scansuite-ci.py.new"
        echo "The downloaded client does not match the server's SHA-256; not running it" >&2
        exit 3
    fi
    mv "$cache/scansuite-ci.py.new" "$cache/scansuite-ci.py"
fi
exec python3 "$cache/scansuite-ci.py" --token-file "$token_file" "$@"
