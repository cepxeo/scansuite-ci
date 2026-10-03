#!/usr/bin/env bash
#
# preflight.sh — what this server, team and token can do, before any scan.
#
#   SCANSUITE_URL=... SCANSUITE_TEAM=... bash preflight.sh
#
# Prints the client and server versions, the token's role, permissions and
# expiry, and every scanner the server offers, marking the ones it cannot run
# for this team. Changes nothing.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${SCANSUITE_URL:?Set SCANSUITE_URL}"
: "${SCANSUITE_TEAM:?Set SCANSUITE_TEAM}"

echo "== Versions"
echo "client: $(bash "$here/ssci.sh" --version 2>&1 | tail -1)"
echo "server: $(curl -fsS "$SCANSUITE_URL/ci/version" 2>&1)"

echo
echo "== Token"
if context="$(bash "$here/api.sh" GET /context)"; then
    printf '%s' "$context" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("role:        %s (%s)" % (d.get("role"), d.get("principal_kind")))
print("expires:     %s" % str(d.get("token_expires_at"))[:10])
print("permissions: %s" % ", ".join(d.get("permissions", [])))
'
else
    echo "The token was refused: check the token file, the team slug and the server URL"
fi

echo
echo "== Scanners this server offers (NOT AVAILABLE ones would be refused)"
bash "$here/ssci.sh" --list-scanners --no-version-check
