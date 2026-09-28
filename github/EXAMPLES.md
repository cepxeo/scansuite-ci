# ScanSuite on GitHub Actions — examples

Two ways to run it, both on the published `appsec4u/scansuite-ci:1` image:

- **The action** ([`action.yml`](action.yml)) — copy `github/` into your repo as
  `.github/actions/scansuite` and `uses:` it. Inputs map to the `SCANSUITE_*` variables.
- **A container job / `docker run` step** — no copying; run the image directly.

Store the token as the repository secret **`SCANSUITE_TOKEN`**. For SARIF upload the
job needs `permissions: security-events: write`, and `actions/checkout` needs
`fetch-depth: 0` so `--changed-only` can find the merge base.

---

## 1. PR gate + default-branch + nightly, with the action

One workflow, three behaviours by event: quick changed-only on PRs, standard on
`main`, deep nightly — plus SARIF upload to code scanning.

```yaml
# .github/workflows/scansuite.yml
name: ScanSuite
on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: "0 2 * * *"

permissions:
  contents: read
  security-events: write        # SARIF upload

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: ./.github/actions/scansuite
        with:
          url: https://scansuite.example.com
          team: appsec
          product: my-service
          token: ${{ secrets.SCANSUITE_TOKEN }}
          profile: ${{ github.event_name == 'pull_request' && 'quick' || github.event_name == 'schedule' && 'deep' || 'standard' }}
          changed-only: ${{ github.event_name == 'pull_request' }}
          block-class: sql_injection,command_injection
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with: { sarif_file: scansuite.sarif }
```

## 2. Fast PR check — quick, changed-only

```yaml
on: { pull_request: {} }
permissions: { contents: read, security-events: write }
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: ./.github/actions/scansuite
        with:
          url: https://scansuite.example.com
          team: appsec
          product: my-service
          token: ${{ secrets.SCANSUITE_TOKEN }}
          profile: quick
          changed-only: "true"
          fail-on-severity: high
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with: { sarif_file: scansuite.sarif }
```

## 3. Release gate on a tag — reachable-only, block injection, keep the report

```yaml
on:
  push:
    tags: ["v*"]
permissions: { contents: read }
jobs:
  release-gate:
    runs-on: ubuntu-latest
    container: appsec4u/scansuite-ci:1
    env:
      SCANSUITE_URL: https://scansuite.example.com
      SCANSUITE_TEAM: appsec
      SCANSUITE_PRODUCT: my-service
      SCANSUITE_TOKEN: ${{ secrets.SCANSUITE_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - run: >
          scansuite-ci --profile standard
          --fail-on-severity medium --min-confidence reachable
          --block-class sql_injection,command_injection --fail-on-secrets all
          --report-zip scansuite-report.zip --summary-json scansuite.json
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: scansuite-report, path: "scansuite-report.zip" }
```

## 4. Container job with a raw command — per-severity budget

Run the image directly as a container job (no action copy needed) and set an
explicit budget.

```yaml
on: { schedule: [{ cron: "0 3 * * *" }] }
permissions: { contents: read }
jobs:
  nightly:
    runs-on: ubuntu-latest
    container: appsec4u/scansuite-ci:1
    env:
      SCANSUITE_URL: https://scansuite.example.com
      SCANSUITE_TEAM: appsec
      SCANSUITE_PRODUCT: my-service
      SCANSUITE_TOKEN: ${{ secrets.SCANSUITE_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: scansuite-ci --profile deep --max high=0,critical=0,medium=10 --timeout 14400 --junit scansuite-junit.xml
```

## 5. Monorepo — one job per service (matrix)

```yaml
on: { pull_request: {} }
permissions: { contents: read }
jobs:
  scan:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [payments, web-frontend]
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: ./.github/actions/scansuite
        with:
          url: https://scansuite.example.com
          team: appsec
          product: ${{ matrix.service }}
          token: ${{ secrets.SCANSUITE_TOKEN }}
          profile: quick
          changed-only: "true"
        env:
          SCANSUITE_EXTRA_ARGS: --source-dir services/${{ matrix.service }}
```

## 6. Report-only rollout — never fail the build (yet)

```yaml
on: { pull_request: {}, push: { branches: [main] } }
permissions: { contents: read, security-events: write }
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: ./.github/actions/scansuite
        with:
          url: https://scansuite.example.com
          team: appsec
          product: my-service
          token: ${{ secrets.SCANSUITE_TOKEN }}
          fail-on-severity: none        # report only; findings still reach code scanning
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with: { sarif_file: scansuite.sarif }
```

---

## Fine-grained AI scans (container job)

The action's inputs cover profiles and the gate, but `--scanners` / `--options` are
CLI-only. To pick exact AI engines and features, run the image as a **container job**
and pass the flags directly. All of these set the three `SCANSUITE_*` env vars on the job:

```yaml
# reused by every job below
    container: appsec4u/scansuite-ci:1
    env:
      SCANSUITE_URL: https://scansuite.example.com
      SCANSUITE_TEAM: appsec
      SCANSUITE_PRODUCT: my-service
      SCANSUITE_TOKEN: ${{ secrets.SCANSUITE_TOKEN }}
```

## 7. Full AI SAST — reachability + architecture + git history (default branch)

```yaml
on: { push: { branches: [main] } }
permissions: { contents: read, security-events: write }
jobs:
  ai-sast:
    runs-on: ubuntu-latest
    container: appsec4u/scansuite-ci:1
    env:
      SCANSUITE_URL: https://scansuite.example.com
      SCANSUITE_TEAM: appsec
      SCANSUITE_PRODUCT: my-service
      SCANSUITE_TOKEN: ${{ secrets.SCANSUITE_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: >
          scansuite-ci --scanners mlsast
          --options mlsast_reachability,mlsast_security_architecture,mlsast_git_history
          --fail-on-severity high --sarif scansuite.sarif --summary-json scansuite.json
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with: { sarif_file: scansuite.sarif }
```

## 8. AI SAST on the PR — changed-only, reachable-only

Only findings the AI confirms an attacker can reach fail the check.

```yaml
on: { pull_request: {} }
permissions: { contents: read, security-events: write }
jobs:
  ai-sast-pr:
    runs-on: ubuntu-latest
    container: appsec4u/scansuite-ci:1
    env:
      SCANSUITE_URL: https://scansuite.example.com
      SCANSUITE_TEAM: appsec
      SCANSUITE_PRODUCT: my-service
      SCANSUITE_TOKEN: ${{ secrets.SCANSUITE_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: >
          scansuite-ci --scanners mlsast --options mlsast_reachability
          --changed-only --min-confidence reachable --fail-on-severity high
          --sarif scansuite.sarif
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with: { sarif_file: scansuite.sarif }
```

## 9. AI dependency checks (SCA) — reachable-only

The AI enriches CVE findings and traces reachability; unreachable CVEs don't block.

```yaml
on: { push: { branches: [main] }, schedule: [{ cron: "0 4 * * *" }] }
permissions: { contents: read }
jobs:
  ai-deps:
    runs-on: ubuntu-latest
    container: appsec4u/scansuite-ci:1
    env:
      SCANSUITE_URL: https://scansuite.example.com
      SCANSUITE_TEAM: appsec
      SCANSUITE_PRODUCT: my-service
      SCANSUITE_TOKEN: ${{ secrets.SCANSUITE_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - run: >
          scansuite-ci --scanners dep_checks --options dep_checks_ai,dep_checks_reachability
          --min-confidence reachable --fail-on-severity high --summary-json scansuite.json
```

## 10. AI secret scanning — verified, new secrets only

Needs `credential.read` on the token (drop it and use `--fail-on-secrets none` otherwise).

```yaml
on: { pull_request: {} }
permissions: { contents: read }
jobs:
  ai-secrets:
    runs-on: ubuntu-latest
    container: appsec4u/scansuite-ci:1
    env:
      SCANSUITE_URL: https://scansuite.example.com
      SCANSUITE_TEAM: appsec
      SCANSUITE_PRODUCT: my-service
      SCANSUITE_TOKEN: ${{ secrets.SCANSUITE_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: >
          scansuite-ci --scanners secrets --options secrets_ai
          --fail-on-severity none --fail-on-secrets new --summary-json scansuite.json
```

## 11. Deep nightly — everything AI, plus the cross-file boundary hunt

AI SAST with reachability + architecture + cross-file hunt (auth/authz/tenant
isolation), AI dependencies and AI secret verification, with a per-severity budget.

```yaml
on: { schedule: [{ cron: "0 2 * * *" }] }
permissions: { contents: read }
jobs:
  ai-deep:
    runs-on: ubuntu-latest
    container: appsec4u/scansuite-ci:1
    env:
      SCANSUITE_URL: https://scansuite.example.com
      SCANSUITE_TEAM: appsec
      SCANSUITE_PRODUCT: my-service
      SCANSUITE_TOKEN: ${{ secrets.SCANSUITE_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - run: >
          scansuite-ci --scanners mlsast,dep_checks,secrets
          --options mlsast_reachability,mlsast_security_architecture,mlsast_boundary_hunt,dep_checks_ai,dep_checks_reachability,secrets_ai
          --max high=0,critical=0,medium=10 --fail-on-secrets all --timeout 14400
          --report-zip scansuite-report.zip
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: scansuite-report, path: scansuite-report.zip }
```
