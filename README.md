# ScanSuite CI/CD client

Run a ScanSuite SAST scan from a pipeline, follow it to completion, and **fail the
build when the scan confirms vulnerabilities or secrets**. The client is shipped as
a container image — `appsec4u/scansuite-ci` — with Python and Git already inside, so
a job only needs Docker. It authenticates with a team **API token**, never a
username or password.

This repository holds **how to run it**: ready-made integrations and worked
examples for GitHub Actions, GitLab CI and Jenkins, plus plain `docker run`
recipes for any other system.

| Path | What it is |
|---|---|
| [`github/action.yml`](github/action.yml) | GitHub Action wrapping the image. |
| [`github/EXAMPLES.md`](github/EXAMPLES.md) | GitHub workflow examples with different parameters. |
| [`gitlab/scansuite.gitlab-ci.yml`](gitlab/scansuite.gitlab-ci.yml) | GitLab CI template. |
| [`gitlab/EXAMPLES.md`](gitlab/EXAMPLES.md) | GitLab job examples with different parameters. |
| [`jenkins/vars/scansuiteScan.groovy`](jenkins/vars/scansuiteScan.groovy) | Jenkins shared-library step. |
| [`jenkins/EXAMPLES.md`](jenkins/EXAMPLES.md) | Jenkins pipeline examples with different parameters. |
| [`examples/docker-run.md`](examples/docker-run.md) | Raw `docker run` invocations for any CI system. |

---

## 1. One-time setup (a team admin, in ScanSuite)

1. Create the product the pipeline reports into, and note its **ID** (or use its exact name).
2. **Teams → your team → People → Service accounts:** create an account (e.g. `ci`) with the **operator** role.
3. Issue a **token** with the permissions below (maximum 90 days).
4. Store it in the CI system as a **masked/secret** variable `SCANSUITE_TOKEN`. Set
   `SCANSUITE_URL` and `SCANSUITE_TEAM` (the team slug) as plain variables.

**Token permissions (least privilege):**

| Permission | Needed |
|---|---|
| `product.read` | Always: finds the product. |
| `scan.execute` | Always: starts the scan. |
| `scan.read` | Always: follows the job and the scan. |
| `finding.read` | Always: reads the findings for the gate. |
| `credential.read` | Only for the secrets gate (`--fail-on-secrets new` or `all`, the default). With `--fail-on-secrets none`, leave it out. |
| `scan.cancel` | Optional: cancels the scan when the pipeline is cancelled or `--cancel-on-timeout` fires. |
| `report.read` | Optional: `--report-zip`. |

The client checks the token before it uploads anything: a missing permission is
**named** and the job exits 3. Give one token to one pipeline, so it can be revoked
alone. When the token expires within 14 days the job log warns.

---

## 2. Running it

The image has Git, so `--changed-only` and `git ls-files` work. Mount the checkout,
pass the three environment variables, and name the product:

```bash
docker run --rm -v "$PWD:/src" -w /src \
    -e SCANSUITE_URL -e SCANSUITE_TEAM -e SCANSUITE_TOKEN \
    appsec4u/scansuite-ci:1 --product-name my-service
```

- `appsec4u/scansuite-ci:<version>`, or **`:1`** for the latest 1.x.
- The token is read from the `SCANSUITE_TOKEN` environment variable (pass it as a
  masked CI secret), or from a file with `--token-file` — **never on the command line.**
- Runners without Docker can fetch a plain-Python client from your own ScanSuite
  server at `"$SCANSUITE_URL/ci/"` (it requires only Python 3.8+ and the standard
  library); the container image is the recommended path and the one documented here.

Every flag has an environment-variable equivalent (`SCANSUITE_*`), so the same
invocation works whether you pass flags or set variables — see the table in §8.

---

## 3. Scan profiles

| Profile | Scanners | Use it for |
|---|---|---|
| `quick` | Rule-based SAST, secrets, dependency checks; no AI | Every merge request: minutes. |
| `standard` (default) | AI SAST with reachability, dependencies and secrets with AI verification | The default branch. |
| `deep` | AI SAST (reachability, architecture review, boundary hunt), full SAST, IaC, dependencies with reachability, secrets | Nightly and release branches: slow, higher AI cost. |

`--profile quick` (env `SCANSUITE_PROFILE`). `--scanners` and `--options` replace a
profile's lists, `--add-scanners sast_quick,iacs_kics` adds to them, and
`--no-ai-verification` drops the AI options.

---

## 4. Scanning only what a merge request changes

`--changed-only` (env `SCANSUITE_CHANGED_ONLY=1`) scans the files changed since the
merge base with the target branch, so a merge request is checked in minutes on a
large repository.

- The base is `--base BRANCH_OR_COMMIT` (env `SCANSUITE_BASE`), or else the target
  branch the CI system reports (GitLab merge requests, GitHub pull requests, Jenkins
  multibranch change requests, Azure DevOps and Bitbucket pull requests). When a
  shallow clone lacks the target branch, the client fetches it — so **check out full
  history** (`fetch-depth: 0`, `GIT_DEPTH`, `clone: depth: full`).
- Only scanners that can be limited to files run: `mlsast`, `sast_quick`, `sast_full`,
  `sast_custom`, `iacs_kics`. Secrets and dependency checks need the whole tree; the
  client says which it dropped. Keep a full scan (e.g. `--profile deep` nightly) for those.
- Nothing changed (or only excluded files): nothing is scanned and the job passes.
- No base found (a branch pipeline, not a merge request): a full scan runs, with a warning.
- It cannot be combined with `--mode` or `--scope`.

---

## 5. Source

`--source auto` (the default) uploads an archive, unless `--git-url` or `--mode incremental`
is given, which makes the server clone the repository.

- **`--source zip`**: archive the checkout on the runner and upload it. In a Git
  checkout only tracked files are included (`git ls-files`), so build output stays out;
  add `--exclude GLOB` for more. Use this for private repositories — nothing leaves the
  runner except the archive. The upload names the repository, branch and commit it was
  cut from, so each finding links to its file and line.
- **`--source git --git-url URL [--branch B]`**: the server clones the repository. URL
  and branch default to what the CI system reports. HTTPS URLs must not contain
  credentials (client and server refuse them). Private repositories use SSH with the
  team's repository credential. The server scans the branch head at clone time.
- **`--mode incremental`** (Git only) scans the changes since the last compatible scan;
  exits 0 if nothing changed. **`--mode custom-scope --scope PATTERN`** scans selected files.

---

## 6. Quality gate

A finding counts when it comes from this scan and is Open or In Progress.

| Option (env) | Effect |
|---|---|
| `--fail-on-severity high` (`SCANSUITE_FAIL_ON_SEVERITY`) | Blocks on findings at or above the severity (default `high`; `none` turns it off). |
| `--max high=0,medium=10` (`SCANSUITE_MAX`) | Allowed findings per severity. A severity named here uses its limit instead of the threshold; the job fails when the count exceeds it. |
| `--block-class sql_injection,command_injection` (`SCANSUITE_BLOCK_CLASS`) | Findings of these vulnerability classes block at any severity. |
| `--min-confidence reachable` (`SCANSUITE_MIN_CONFIDENCE`) | Only findings AI verification confirmed reachable (or with a known exploit) block. The default `any` also blocks on findings not assessed. |
| `--include-unreachable` | Also block on findings AI verification marked Unreachable (ignored by default). |
| `--fail-on-secrets new` (`SCANSUITE_FAIL_ON_SECRETS`) | Blocks on secrets this run added that are verified or never judged. `all` blocks on every such secret of the product; `none` turns the secrets gate off. |

Every blocking item is printed with the rule that blocked it ("Blocks because: High
severity", "Medium: 12 found, 10 allowed", "blocked class sql_injection"), in the job
log and in the JUnit report.

---

## 7. Exit codes

| Code | Meaning |
|---|---|
| 0 | The gate passed, or there was nothing to scan (incremental or changed-only). |
| 1 | The gate failed: blocking findings and/or secrets. |
| 2 | The scan failed, was cancelled, or was refused (team scan limit, missing credential). |
| 3 | Configuration error: a bad option, an invalid/expired token (HTTP 401), a missing permission (HTTP 403, named), or an untrusted TLS certificate. |
| 4 | Timed out waiting (`--timeout`, default 7200 s). |
| 5 | The ScanSuite server was unreachable or returned an error. |

With `--soft-fail`, codes 2, 4 and 5 become 0 with a warning, so a ScanSuite outage
does not block releases. Findings (1) and misconfiguration (3) still fail the job.

---

## 8. Reports, TLS and options

**Reports**
- `--junit` — JUnit XML, shown as test failures in GitLab and Jenkins.
- `--sarif` — SARIF 2.1.0, for GitHub code scanning and Azure DevOps.
- `--summary-json` — the scan, gate result, findings and secrets. **Secret values are never included.**
- `--report-zip` — the full report archive.

**TLS.** A self-signed certificate, or one from a CA the runner does not know, gives a
warning and the run continues without verification. To verify it, give the CA with
`--ca-bundle` (env `SCANSUITE_CA_BUNDLE`); to stop instead (exit 3), use `--strict-tls`
(env `SCANSUITE_STRICT_TLS=1`). A CA-signed certificate for another host, or an expired
one, always stops the run. `--insecure` turns verification off from the start — testing only.

**Full option / environment-variable reference**

| Flag | Env | Notes |
|---|---|---|
| `--url` | `SCANSUITE_URL` | ScanSuite server URL. Required. |
| `--team` | `SCANSUITE_TEAM` | Team slug. Required. |
| `--token-file` | `SCANSUITE_TOKEN` (env) | Token from a file, or the masked env var. |
| `--product-name` / `--product-id` | `SCANSUITE_PRODUCT` / `SCANSUITE_PRODUCT_ID` | Product to report into. |
| `--profile` | `SCANSUITE_PROFILE` | `quick` / `standard` / `deep`. |
| `--changed-only`, `--base` | `SCANSUITE_CHANGED_ONLY`, `SCANSUITE_BASE` | Scan only changed files. |
| `--source`, `--source-dir`, `--exclude`, `--git-url`, `--branch`, `--mode`, `--scope` | `SCANSUITE_SOURCE`, `SCANSUITE_GIT_URL`, `SCANSUITE_BRANCH` | Where the code comes from. |
| `--scanners`, `--add-scanners`, `--options`, `--no-ai-verification`, `--lang` | — | Override the profile's engines. |
| `--fail-on-severity`, `--max`, `--block-class`, `--min-confidence`, `--include-unreachable`, `--fail-on-secrets`, `--soft-fail` | `SCANSUITE_FAIL_ON_SEVERITY`, `SCANSUITE_MAX`, `SCANSUITE_BLOCK_CLASS`, `SCANSUITE_MIN_CONFIDENCE`, `SCANSUITE_FAIL_ON_SECRETS` | The quality gate. |
| `--junit`, `--sarif`, `--summary-json`, `--report-zip` | — | Report outputs. |
| `--ca-bundle`, `--strict-tls`, `--insecure` | `SCANSUITE_CA_BUNDLE`, `SCANSUITE_STRICT_TLS` | TLS. |
| `--timeout`, `--poll-interval`, `--no-wait`, `--cancel-on-timeout`, `--idempotency-key` | `SCANSUITE_TIMEOUT`, `SCANSUITE_IDEMPOTENCY_KEY` | Waiting and retries. |
| `--version`, `--no-version-check` | — | Version. |

---

## 9. Platform integrations

| Platform | Start here |
|---|---|
| **GitHub Actions** | [`github/action.yml`](github/action.yml) + [`github/EXAMPLES.md`](github/EXAMPLES.md) |
| **GitLab CI** | [`gitlab/scansuite.gitlab-ci.yml`](gitlab/scansuite.gitlab-ci.yml) + [`gitlab/EXAMPLES.md`](gitlab/EXAMPLES.md) |
| **Jenkins** | [`jenkins/vars/scansuiteScan.groovy`](jenkins/vars/scansuiteScan.groovy) + [`jenkins/EXAMPLES.md`](jenkins/EXAMPLES.md) |
| **Any other system** (Azure DevOps, Bitbucket, CircleCI, TeamCity, Drone, Tekton, cron) | [`examples/docker-run.md`](examples/docker-run.md) |

The client recognises GitLab, GitHub, Jenkins, Azure DevOps and Bitbucket from their
environment variables. Anywhere else, give it what it cannot guess: the `--base` for
`--changed-only`, and a per-run `--idempotency-key` so a retried step never starts a
second scan.
