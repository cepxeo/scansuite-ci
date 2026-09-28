# ScanSuite CI/CD client

Run a ScanSuite scan from your pipeline, wait for it, and **fail the build when it
finds real problems** — vulnerabilities, vulnerable dependencies, or leaked secrets.
Everything ships in one container image, `appsec4u/scansuite-ci`, with Python and Git
already inside, so a CI job only needs Docker.

This repo is **how to run it**: copy-paste command examples and ready-made
integrations for GitHub Actions, GitLab CI and Jenkins.

---

## What you need

1. **Docker** on the runner.
2. Your **server URL** and **team slug** → `SCANSUITE_URL`, `SCANSUITE_TEAM`.
3. An **API token**. In ScanSuite: *Teams → your team → People → Service accounts* →
   create an `operator` account and issue a token. Store it as the **masked** CI
   secret `SCANSUITE_TOKEN`. (The client checks the token up front and, if a
   permission is missing, names it and exits 3 — so you never have to guess.)
4. The **product** to report into → `--product-name` (or `--product-id`).

That's it. Set the three variables once and every example below just works.

---

## Quick start

The client reads `SCANSUITE_URL`, `SCANSUITE_TEAM`, `SCANSUITE_TOKEN` from the
environment, so the token isn't written on the command line (where `ps` would expose
it). Mount your checkout at `/src` and run there:

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service --profile standard
```

`--profile standard` is AI static analysis with reachability, dependency checks and
AI-verified secrets — a good default for a branch. The rest of this page shows how to
shape that for pull requests, nightly runs, release gates and single-purpose scans.

> Every example uses these three env vars. Export them once in your shell to try the
> commands locally:
> ```bash
> export SCANSUITE_URL=https://scansuite.example.com SCANSUITE_TEAM=appsec SCANSUITE_TOKEN=****
> ```

### Handling the token

The token is a credential, so treat it like one. The examples and scripts here pass it
to the container through the `SCANSUITE_TOKEN` **environment variable** — never as a
command-line argument (which `ps` would expose) — and never echo it. That's the limit of
what a shell can do: **it can't "mask" or hide a value it holds.** The redaction you see
in job logs is done by your CI platform when the token is stored as a *masked/secret*
variable, not by any script. So: **in CI, always store it as the platform's masked
secret**; running locally, keep it out of your shell history and files (`--token-file`
reads it from a file instead of the environment).

---

## Practical examples

Complete commands, grouped by what you want to scan. Swap `my-service` for your
product and add report flags (`--junit`, `--sarif`, `--summary-json`) as your CI needs.

> **Note on `credential.read`.** The secrets gate is on by default
> (`--fail-on-secrets new`) and is checked at startup, so the token needs the
> `credential.read` permission unless you turn the gate off. A **code-only** scan
> (SAST-only or dependencies-only) doesn't read secrets — add **`--fail-on-secrets none`**
> to run it with a minimal token that has no `credential.read` (as
> [`examples/ai-sast-pr.sh`](examples/ai-sast-pr.sh) does).

### AI static analysis (SAST)

**Pull request — AI SAST on just the changed files, block what's reachable.**
Fast enough for every PR; only findings the AI confirms an attacker can reach fail the build.

```bash
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service \
    --scanners mlsast --options mlsast_reachability \
    --changed-only --base origin/main \
    --min-confidence reachable --fail-on-severity high \
    --sarif scansuite.sarif
```

**Default branch — full AI SAST with reachability, architecture review and git history.**
The whole repo, the model reasoning about auth/trust boundaries and recent commits.

```bash
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service \
    --scanners mlsast \
    --options mlsast_reachability,mlsast_security_architecture,mlsast_git_history \
    --fail-on-severity high --summary-json scansuite.json
```

**Deep nightly — add the cross-file hunt for auth/authz/tenant-isolation bugs.**
Slower and higher AI cost; run it on a schedule, not on every push.

```bash
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service \
    --scanners mlsast,sast_full \
    --options mlsast_reachability,mlsast_security_architecture,mlsast_boundary_hunt \
    --max high=0,critical=0,medium=10 --timeout 14400
```

**Block a class of bug regardless of severity.**
Fail on injection anywhere it appears, even Low.

```bash
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service \
    --scanners mlsast --options mlsast_reachability \
    --fail-on-severity none --block-class sql_injection,command_injection,path_traversal
```

### Dependency checks (SCA) with AI

**AI-enriched dependencies, reachable-only gate.**
Scans manifests for known-vulnerable libraries; the AI adds context and traces whether
the vulnerable code is actually reachable, so unreachable CVEs don't block the build.

```bash
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service \
    --scanners dep_checks --options dep_checks_ai,dep_checks_reachability \
    --min-confidence reachable --fail-on-severity high --summary-json scansuite.json
```

**Dependencies only, strict — any High/Critical CVE fails.**

```bash
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service \
    --scanners dep_checks --options dep_checks_ai --fail-on-severity high
```

### Secret scanning with AI

**Block only on real, newly introduced secrets.**
The AI verifies candidates (drops test fixtures and false positives) and the gate fails
only on secrets this run adds to the product — so an existing backlog doesn't block PRs.

```bash
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service \
    --scanners secrets --options secrets_ai \
    --fail-on-severity none --fail-on-secrets new
```
> The secrets gate needs the `credential.read` permission on the token. If your token
> doesn't have it, add `--fail-on-secrets none` (and drop `secrets`).

### Everything together, with AI

**Release gate — AI SAST + AI dependencies + AI secrets, reachable-only, keep the report.**
Blocks on reachable findings from Medium up, on injection at any severity, and on every
open secret; downloads the full report to attach to the release.

```bash
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service --profile deep \
    --min-confidence reachable --fail-on-severity medium \
    --block-class sql_injection,command_injection --fail-on-secrets all \
    --report-zip scansuite-report.zip --summary-json scansuite.json
```

### Fast, no AI

**Rule-based PR check — SAST + secrets + dependencies, no model cost, seconds to run.**

```bash
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service \
    --profile quick --changed-only --base origin/main --junit scansuite-junit.xml
```

### Rolling ScanSuite out — report first, block later

Nothing fails yet; findings still show up as test results and in code scanning.
Tighten with a budget once the team has cleaned up.

```bash
# phase 1 — visibility only
docker run --rm -v "$PWD:/src" -w /src -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service --profile standard \
    --fail-on-severity none --fail-on-secrets none --sarif scansuite.sarif

# phase 2 — allow today's count, and never let a ScanSuite outage block a release
    ... --max high=8,critical=0 --soft-fail
```

---

## Choosing scanners and AI features

Use a **profile** for the common cases, or name scanners and options for fine control.

| Profile | What runs | Good for |
|---|---|---|
| `quick` | Rule-based SAST, secrets, dependencies — **no AI** | Every PR, in minutes |
| `standard` (default) | **AI SAST** + reachability, dependencies + AI, secrets + AI | The default branch |
| `deep` | AI SAST + reachability + architecture + cross-file hunt, full SAST, IaC, dependencies + reachability, secrets | Nightly / release |

Compose your own instead:

- `--scanners LIST` — the engines to run: `mlsast` (AI SAST), `sast_quick`, `sast_full`,
  `dep_checks`, `secrets`, `iacs_kics` (IaC).
- `--options LIST` — the AI features to turn on:
  `mlsast_reachability`, `mlsast_security_architecture`, `mlsast_git_history`,
  `mlsast_boundary_hunt`, `dep_checks_ai`, `dep_checks_reachability`, `secrets_ai`.
- `--add-scanners LIST` — add to a profile instead of replacing it.
- `--no-ai-verification` — keep the scanners but drop all the AI options (e.g. to save cost).

---

## Scan scope

- **`--changed-only`** scans only the files changed since the target branch — check out
  full history (`fetch-depth: 0`, `GIT_DEPTH`) and give `--base BRANCH` when the CI
  system can't report it. In a PR pipeline the base is detected automatically. Only
  file-limitable engines run this way (`mlsast`, `sast_*`, `iacs_kics`); keep a full
  scan on a schedule for dependencies and secrets.
- **`--source zip`** (default when uploading) sends only tracked files (`git ls-files`);
  **`--source git --git-url URL`** has the server clone it (SSH for private repos — HTTPS
  URLs must not contain credentials). **`--mode incremental`** scans only what changed
  since the last scan and passes when nothing did.
- **`--source-dir PATH`** points a run at one service in a monorepo.

---

## The quality gate

A finding counts when it comes from this scan and is Open or In Progress.

| Flag | Effect |
|---|---|
| `--fail-on-severity high` | Block at or above this severity (default `high`; `none` = off). |
| `--max high=0,medium=10` | Per-severity budgets — fail when the count exceeds the limit. |
| `--block-class sql_injection,command_injection` | These classes block at **any** severity. |
| `--min-confidence reachable` | Only findings the AI confirms reachable block (default `any`). |
| `--fail-on-secrets new` | Block on new verified secrets (`all` = every open secret, `none` = off). |
| `--soft-fail` | A scan/timeout/server error passes with a warning; real findings still fail. |

Every blocking item is printed with the exact rule that blocked it, in the log and the
JUnit report.

---

## Exit codes

| Code | Meaning |
|---|---|
| **0** | Gate passed, or nothing to scan. |
| **1** | Gate failed — blocking findings and/or secrets. |
| **2** | Scan failed, cancelled, or refused (scan limit, missing credential). |
| **3** | Configuration — bad option, invalid/expired token, missing permission (named), untrusted TLS. |
| **4** | Timed out (`--timeout`, default 7200 s). |
| **5** | Server unreachable or errored. |

`--soft-fail` turns 2/4/5 into 0.

---

## Reports & TLS

- `--junit` (test results in GitLab/Jenkins), `--sarif` (GitHub code scanning /
  Azure DevOps), `--summary-json` (findings; **secret values never included**),
  `--report-zip` (full archive).
- A self-signed or unknown-CA certificate → the run **warns and continues unverified**.
  Verify it with `--ca-bundle FILE`, or refuse with `--strict-tls`. `--insecure` skips
  verification entirely (testing only).

---

## Platform integrations

| Platform | Start here |
|---|---|
| **GitHub Actions** | [`github/action.yml`](github/action.yml) + [`github/EXAMPLES.md`](github/EXAMPLES.md) |
| **GitLab CI** | [`gitlab/scansuite.gitlab-ci.yml`](gitlab/scansuite.gitlab-ci.yml) + [`gitlab/EXAMPLES.md`](gitlab/EXAMPLES.md) |
| **Jenkins** | [`jenkins/vars/scansuiteScan.groovy`](jenkins/vars/scansuiteScan.groovy) + [`jenkins/EXAMPLES.md`](jenkins/EXAMPLES.md) |
| **Anything else** (Azure, Bitbucket, CircleCI, cron…) | [`examples/docker-run.md`](examples/docker-run.md) |

Each integration passes the same flags shown above through `SCANSUITE_*` variables, so
anything you can do on the command line you can do in a pipeline.
