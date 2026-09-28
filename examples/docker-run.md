# Running scansuite-ci with `docker run`

Every example uses the published image `appsec4u/scansuite-ci:1`. They assume these
are exported in the environment (the **token is always a masked secret**, never on
the command line):

```bash
export SCANSUITE_URL=https://scansuite.example.com
export SCANSUITE_TEAM=appsec
export SCANSUITE_PRODUCT=my-service        # or use --product-id 42
export SCANSUITE_TOKEN=****                # masked CI secret
```

The common shape — mount the checkout at `/src`, run there, forward the variables:

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 [OPTIONS]
```

### Ready-made scripts

If you'd rather call a script than remember flags, this folder ships three:

| Script | What it does |
|---|---|
| [`scan.sh`](scan.sh) | General wrapper — set `SCANSUITE_*`, pass any flags, get proper exit-code messages. |
| [`ai-sast-pr.sh`](ai-sast-pr.sh) | AI SAST on the changed files of a PR, reachable-only gate. |
| [`ai-deep-nightly.sh`](ai-deep-nightly.sh) | Full AI scan (SAST + dependencies + secrets) with a per-severity budget, for a nightly cron. |

```bash
export SCANSUITE_URL=https://scansuite.example.com SCANSUITE_TEAM=appsec \
       SCANSUITE_PRODUCT=my-service SCANSUITE_TOKEN=****
./examples/scan.sh --changed-only --base origin/main
```

---

### 1. Merge/pull request — fast, only what changed
Rule-based SAST on the changed files, in minutes; blocks on High and Critical.

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --profile quick --changed-only --base origin/main \
    --junit scansuite-junit.xml --sarif scansuite.sarif
```

### 2. Default branch — AI SAST with reachability
The whole repository, dependencies and secrets verified by AI.

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --profile standard --summary-json scansuite.json
```

### 3. Nightly — everything, with a per-severity budget
No High or Critical at all, at most 10 Medium, whatever the class.

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --profile deep --fail-on-severity high --max high=0,critical=0,medium=10 --timeout 14400
```

### 4. Release gate — zero tolerance for what attackers can reach
Blocks on reachable findings from Medium up, on SQL/command injection at any
severity, and on every open secret of the product; keeps the full report.

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --profile standard --fail-on-severity medium --min-confidence reachable \
    --block-class sql_injection,command_injection --fail-on-secrets all \
    --report-zip scansuite-report.zip
```

### 5. Block only on a class of bug, at any severity
Fail the build on injection findings regardless of severity; ignore everything else.

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --fail-on-severity none --block-class sql_injection,command_injection,path_traversal
```

### 6. Reachable-only gate
Only findings AI verification confirmed reachable (or with a known exploit) block.

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --profile standard --min-confidence reachable --fail-on-severity medium
```

### 7. Introduce ScanSuite — report first, block later
Nothing blocks yet; findings still show up as test results and code scanning.

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --fail-on-severity none --fail-on-secrets none \
    --junit scansuite-junit.xml --sarif scansuite.sarif
```
Then allow today's count and tighten over time (`--soft-fail` also lets outages pass):
```bash
    appsec4u/scansuite-ci:1 --max high=12,critical=0 --soft-fail
```

### 8. Monorepo — one product per service
Point each run at its directory; `--changed-only` then sees only that directory.

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 \
    --source-dir services/payments --product-name payments --profile quick --changed-only
```

### 9. Custom scope — scan selected paths only
```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --mode custom-scope --scope "src/**/*.java" --scope "config/**"
```

### 10. Infrastructure-as-code only
```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --scanners iacs_kics --options "" --fail-on-severity medium
```

### 11. Large repository — let the server clone (nothing uploaded)
The server clones over SSH with the team's repository credential; `--mode incremental`
scans only what changed since the last scan of the branch.

```bash
docker run --rm \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --source git --git-url git@gitlab.example.com:shop/backend.git --branch main --mode incremental
```

### 12. Private CA or self-signed server
Verify the certificate with your CA (mount it in), or refuse to continue.

```bash
# verify with a corporate CA:
docker run --rm -v "$PWD:/src" -w /src -v /etc/ssl/corp:/ca:ro \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 --ca-bundle /ca/root.pem --profile quick

# or stop on any untrusted certificate instead of warning:
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 --strict-tls --profile quick
```

### 13. Token from a file instead of the environment
```bash
docker run --rm -v "$PWD:/src" -w /src -v "$HOME/.config/scansuite:/cfg:ro" \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 --token-file /cfg/token --profile quick --changed-only --base origin/main
```

### 14. Start and move on — don't wait or gate
After a merge, start the scan and let ScanSuite collect the results.

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 --profile deep --no-wait
```

### 15. Unknown CI system — supply what it can't guess
Give the base branch and a per-build idempotency key (so a retried step never
starts a second scan).

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN -e SCANSUITE_PRODUCT \
    appsec4u/scansuite-ci:1 \
    --profile quick --changed-only --base origin/main \
    --idempotency-key "build-$BUILD_NUMBER" \
    --junit scansuite-junit.xml --sarif scansuite.sarif
```

> **Exit codes:** `0` gate passed / nothing to scan · `1` gate failed · `2` scan
> failed/cancelled/refused · `3` configuration (bad option, bad token, missing
> permission, untrusted TLS) · `4` timed out · `5` server unreachable. `--soft-fail`
> turns 2/4/5 into 0.
