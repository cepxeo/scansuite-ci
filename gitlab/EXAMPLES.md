# ScanSuite on GitLab CI — examples

Everything here was run on GitLab CE with a self-hosted runner against a ScanSuite Teams
server. Start with **Quick start**, copy the **starter pipeline**, then pick from the
recipes.

- [Quick start](#quick-start)
- [The starter pipeline](#the-starter-pipeline)
- [Which bundle for which trigger](#which-bundle-for-which-trigger)
- [Make the gate block merges](#make-the-gate-block-merges)
- [Recipes](#recipes)
- [Troubleshooting](#troubleshooting)

---

## Quick start

**1. A token.** In ScanSuite: *Teams → People → Automation and API tokens*, create a
service account with the **Operator** role, then **New token** with the **CI pipeline**
preset. Copy it; it is shown once.

**2. The project's variables** (*Settings → CI/CD → Variables*):

| Variable | Value | Flags |
|---|---|---|
| `SCANSUITE_URL` | `https://scansuite.example.com` | — |
| `SCANSUITE_TEAM` | your team's slug, e.g. `appsec` | — |
| `SCANSUITE_PRODUCT` | the product's exact name (or `SCANSUITE_PRODUCT_ID`) | — |
| `SCANSUITE_TOKEN` | the token | **Masked**. Leave **Protected off** unless every pipeline that scans runs on a protected branch or tag |

> **Protected variables never reach merge request pipelines from unprotected branches.**
> With `SCANSUITE_TOKEN` protected, the merge request job stops with
> `Set SCANSUITE_TOKEN ...` (exit code 3). Keep it unprotected, or protect the branches
> merge requests come from.

`SCANSUITE_EXTRA_ARGS` passes any other client option to a job.

> **Project variables win over variables in `.gitlab-ci.yml`.** A job's
> `SCANSUITE_PRODUCT: other` is ignored while the project defines `SCANSUITE_PRODUCT`. To
> vary something per job, pass the option instead (`SCANSUITE_EXTRA_ARGS: --product-name other`;
> options win over variables), or leave that variable out of the project's settings.

**3. A runner** with the **Docker executor** that can pull `appsec4u/scansuite-ci:1` and
reach your ScanSuite server over HTTPS. The template's jobs have no tags, so the runner
must accept untagged jobs — or add your tags to `.scansuite`:

```yaml
.scansuite:
  tags: [docker]
```

The scans run on the ScanSuite server; the job only uploads the code and waits, so a
small runner is enough.

**4. Include the template** your ScanSuite server serves (it always matches the server):

```yaml
include:
  - remote: 'https://scansuite.example.com/ci/scansuite.gitlab-ci.yml'
```

That alone adds two jobs:

| Job | When | Bundle |
|---|---|---|
| `scansuite-merge-request` | every merge request | `quick-classic` on the changed files only |
| `scansuite-default-branch` | pushes to the default branch | `standard-ai` on everything |

Both upload `scansuite-junit.xml` (shown in the pipeline's **Tests** tab and the merge
request), `scansuite.json` and `scansuite.sarif`, even when the job fails.

---

## The starter pipeline

The pipeline this page was tested with: the template's two jobs, a static scan without
AI, a DAST scan of the deployed application and a scan of the container image.

```yaml
include:
  - remote: 'https://scansuite.example.com/ci/scansuite.gitlab-ci.yml'

stages: [test, verify]

# Static analysis without AI: Semgrep with the full ruleset, secrets, dependencies.
scansuite-standard-classic:
  extends: .scansuite
  variables:
    SCANSUITE_PROFILE: standard-classic
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE != "merge_request_event"

# DAST of the deployed application.
scansuite-dast:
  extends: .scansuite
  stage: verify
  needs: []          # run even when a static scan failed the build
  variables:
    SCANSUITE_SCAN_TYPE: dast
    SCANSUITE_TARGETS: https://staging.example.com
    SCANSUITE_PROFILE: quick
    SCANSUITE_FAIL_ON_SEVERITY: critical
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE != "merge_request_event"

# The image the release ships.
scansuite-image:
  extends: .scansuite
  stage: verify
  needs: []
  variables:
    SCANSUITE_SCAN_TYPE: infra
    SCANSUITE_TARGETS: registry.example.com/shop/api:$CI_COMMIT_SHORT_SHA
    SCANSUITE_EXTRA_ARGS: --scanners docker_image_scan
    SCANSUITE_FAIL_ON_SEVERITY: critical
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE != "merge_request_event"
```

What the test run showed, on a sample application with known problems:

| Job | Result | Why |
|---|---|---|
| `scansuite-merge-request` | passed | `report.py` changed; `quick-classic` found nothing at High in it (see the next section) |
| `scansuite-default-branch` | failed, exit 1 | AI SAST: command injection, SQL injection, path traversal, all reachable; one verified secret |
| `scansuite-standard-classic` | failed, exit 1 | Semgrep findings and vulnerable dependencies (pyyaml, flask, jinja2, requests) |
| `scansuite-dast` | passed | High and Medium findings, below the `critical` threshold |
| `scansuite-image` | failed, exit 1 | 9 Critical CVEs in the image |

Without `needs: []` GitLab skips the `verify` jobs as soon as a `test` job fails, which is
exactly when you want them to run.

DAST and infrastructure targets must be in your team's allowed targets (*Teams →
Scanning*); a target outside them stops the job with exit code 3 before any scan starts.

---

## Which bundle for which trigger

| Trigger | Without AI | With AI |
|---|---|---|
| Merge request (`SCANSUITE_CHANGED_ONLY: "1"`) | `quick-classic` | `quick-ai` |
| Default branch | `standard-classic` | `standard-ai` |
| Nightly or release (schedule, tag) | `full-classic` | `full-ai` |

- **`quick-classic` is rule-based Semgrep only.** It is fast, but in the tests it let merge
  requests through that added `pickle.loads(request.data)` and `eval(request.args[...])` in
  Python, and a shell command built from the request in JavaScript (`exec("ping " + req.query.host)`).
  If your team has AI, `quick-ai` is the stronger merge request gate:

  ```yaml
  scansuite-merge-request:
    variables:
      SCANSUITE_PROFILE: quick-ai
  ```

- **The AI bundles report only secrets AI verification confirmed.** The documented example
  AWS key in the test repository was rejected; a real-looking GitHub token was reported.
- **`full-ai` analyses Git history**, so give it the whole history: `GIT_DEPTH: "0"`.
- `--list-scanners` (run the image with it) prints the bundles and what your server can
  run; a scanner the server cannot run for your team stops the job with exit code 3 and
  says what to set up.

---

## Make the gate block merges

A failed ScanSuite job blocks a merge only if the project requires it:
*Settings → Merge requests → Merge checks → **Pipelines must succeed***.

GitLab CE shows the JUnit report (one failed test per blocking finding or secret) in the
pipeline's **Tests** tab and in the merge request. The SARIF file is kept as an artifact;
showing it inline needs GitLab Ultimate's security dashboard.

To roll out without blocking anyone yet, see [report-only rollout](#report-only-rollout).

---

## Recipes

### Tighter merge request gate

Block injection at any severity, on top of the severity threshold:

```yaml
scansuite-merge-request:
  variables:
    SCANSUITE_BLOCK_CLASS: sql_injection,command_injection,code_injection
```

### Nightly full scan with a budget

Run it from *CI/CD → Schedules*:

```yaml
scansuite-nightly:
  extends: .scansuite
  variables:
    SCANSUITE_PROFILE: full-ai
    GIT_DEPTH: "0"
    SCANSUITE_MAX: high=0,critical=0,medium=10
    SCANSUITE_TIMEOUT: "14400"
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
```

### Release gate on tags

Reachable findings only, every secret the product has, the full report kept:

```yaml
scansuite-release:
  extends: .scansuite
  stage: release
  variables:
    SCANSUITE_PROFILE: standard-ai
    SCANSUITE_FAIL_ON_SEVERITY: medium
    SCANSUITE_MIN_CONFIDENCE: reachable
    SCANSUITE_FAIL_ON_SECRETS: all
    SCANSUITE_EXTRA_ARGS: --report-zip scansuite-report.zip
  artifacts:
    when: always
    paths: [scansuite-report.zip, scansuite.json]
  rules:
    - if: $CI_COMMIT_TAG
```

### Monorepo — one product per service

```yaml
scansuite-services:
  extends: .scansuite
  parallel:
    matrix:
      - SERVICE: [payments, web]
  variables:
    SCANSUITE_PROFILE: quick-classic
    SCANSUITE_CHANGED_ONLY: "1"
    # An option, not SCANSUITE_PRODUCT: the project's variable would win over a job variable.
    SCANSUITE_EXTRA_ARGS: --source-dir services/$SERVICE --product-name $SERVICE --create-product
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

### Create the product on the first run

The first run creates the product, every later run finds it (the CI pipeline token preset
allows creating products):

```yaml
.scansuite:
  variables:
    SCANSUITE_EXTRA_ARGS: --product-name $CI_PROJECT_NAME --create-product
```

A job that sets its own `SCANSUITE_EXTRA_ARGS` replaces this value, so repeat the two
options there. Or set `SCANSUITE_PRODUCT` and `SCANSUITE_CREATE_PRODUCT=1` as project
variables.

### Report-only rollout

Scan and publish the reports, never fail the pipeline:

```yaml
scansuite-default-branch:
  variables:
    SCANSUITE_FAIL_ON_SEVERITY: none
    SCANSUITE_FAIL_ON_SECRETS: none
```

To tolerate a ScanSuite outage but still fail on findings, add
`SCANSUITE_EXTRA_ARGS: --soft-fail` instead (exit codes 2, 4 and 5 become 0).

### Large repository — the server clones it

Nothing is uploaded from the runner; the server clones the branch and, with
`--mode incremental`, scans only what changed since its last scan of it. For a private
project, add the team's SSH public key (*Teams → Scanning*) to the GitLab project as a
**deploy key**, and give the SSH clone URL:

```yaml
scansuite-incremental:
  extends: .scansuite
  variables:
    SCANSUITE_SOURCE: git
    SCANSUITE_GIT_URL: git@gitlab.example.com:$CI_PROJECT_PATH.git
    SCANSUITE_PROFILE: standard-ai
    SCANSUITE_EXTRA_ARGS: --mode incremental
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

### Private CA

```yaml
.scansuite:
  variables:
    SCANSUITE_CA_BUNDLE: ci/corp-root.pem
    # or refuse any certificate the runner does not trust, instead of warning:
    # SCANSUITE_STRICT_TLS: "1"
```

### Without the template

Clear the image's entrypoint (GitLab runs its own shell):

```yaml
scansuite:
  stage: test
  image:
    name: appsec4u/scansuite-ci:1
    entrypoint: [""]
  variables:
    GIT_DEPTH: "50"
  script:
    - scansuite-ci --profile quick-classic --changed-only --junit scansuite-junit.xml --sarif scansuite.sarif
  artifacts:
    when: always
    reports: { junit: scansuite-junit.xml }
    paths: [scansuite.sarif]
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

### Fine-grained AI scans

`--scanners` and `--options` replace a bundle's; pass them through `SCANSUITE_EXTRA_ARGS`.

```yaml
# AI SAST with every option, on the default branch.
scansuite-ai-sast:
  extends: .scansuite
  variables:
    GIT_DEPTH: "0"
    SCANSUITE_EXTRA_ARGS: >-
      --scanners mlsast
      --options mlsast_reachability,mlsast_security_architecture,mlsast_boundary_hunt,mlsast_git_history

# Dependencies: only CVEs AI confirmed reachable block.
scansuite-ai-deps:
  extends: .scansuite
  variables:
    SCANSUITE_MIN_CONFIDENCE: reachable
    SCANSUITE_EXTRA_ARGS: --scanners dep_checks --options dep_checks_reachability

# Secrets: only verified ones this run found.
scansuite-ai-secrets:
  extends: .scansuite
  variables:
    SCANSUITE_FAIL_ON_SEVERITY: none
    SCANSUITE_FAIL_ON_SECRETS: new
    SCANSUITE_EXTRA_ARGS: --scanners secrets --options secrets_ai
```

---

## Troubleshooting

GitLab shows the client's exit code as `ERROR: Job failed: exit code N`:

| Exit code | Meaning | What to do |
|---|---|---|
| 1 | The gate blocked: findings or secrets | Read the `BLOCKING` lines in the log or the **Tests** tab |
| 2 | The scan failed, was cancelled or refused, or one of its scanners did not complete | The log names the scanners that did not complete |
| 3 | Configuration: option, token, permission, target or certificate | The last `[scansuite]` line says what is wrong |
| 4 | Timed out waiting | Raise `SCANSUITE_TIMEOUT` (seconds) |
| 5 | ScanSuite unreachable | Check the runner's network path to the server |

Common configuration errors:

- **`Set SCANSUITE_TOKEN ...`** — the variable did not reach the job; usually it is
  *Protected* and the pipeline runs on an unprotected branch.
- **`The API token lacks permission(s): credential.read`** — the token was issued without
  the CI pipeline preset; issue a new one, or set `SCANSUITE_FAIL_ON_SECRETS: none`.
- **Findings land in the wrong product** — the project's `SCANSUITE_PRODUCT` variable
  overrides the job's; pass `--product-name` in `SCANSUITE_EXTRA_ARGS` instead.
- **`Cannot run on this server: openvas: ...`** — that scanner is not set up for your team;
  the message says where to set it up.
- **`--changed-only: no base to compare with`** — not a merge request pipeline, or the
  clone lacks the target branch; the job then scans everything.
- **`This is a shallow clone, so Git history analysis sees only ...`** — set
  `GIT_DEPTH: "0"` for `full-ai` and other Git history scans.
