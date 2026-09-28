# ScanSuite on GitLab CI — examples

The template [`scansuite.gitlab-ci.yml`](scansuite.gitlab-ci.yml) is also served by
your ScanSuite server, so you can `include:` the version that matches it. It defines a
hidden `.scansuite` job on the `appsec4u/scansuite-ci:1` image; extend it or tune it
through `SCANSUITE_*` variables.

Set under **Settings → CI/CD → Variables**: `SCANSUITE_URL`, `SCANSUITE_TEAM`,
`SCANSUITE_PRODUCT` (or `SCANSUITE_PRODUCT_ID`), and `SCANSUITE_TOKEN` (**Masked,
Protected**). `SCANSUITE_EXTRA_ARGS` passes extra client flags to any job.

---

## 1. Default two jobs — just include the template

Adds `scansuite-merge-request` (quick, changed-only, on every MR) and
`scansuite-default-branch` (standard, on the default branch).

```yaml
include:
  - remote: 'https://scansuite.example.com/ci/scansuite.gitlab-ci.yml'
```

## 2. A full pipeline — MR gate, nightly, release, monorepo

```yaml
include:
  - remote: 'https://scansuite.example.com/ci/scansuite.gitlab-ci.yml'

stages: [build, test, release]

# Tighter MR gate than the template default: also block injection at any severity.
scansuite-merge-request:
  variables:
    SCANSUITE_BLOCK_CLASS: sql_injection,command_injection

# Nightly deep scan (CI/CD > Schedules), with a per-severity budget.
scansuite-nightly:
  extends: .scansuite
  variables:
    SCANSUITE_PROFILE: deep
    SCANSUITE_MAX: high=0,critical=0,medium=10
    SCANSUITE_EXTRA_ARGS: --timeout 14400
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"

# Release gate on tags: reachable-only, block secrets, keep the report.
scansuite-release:
  extends: .scansuite
  stage: release
  variables:
    SCANSUITE_PROFILE: standard
    SCANSUITE_FAIL_ON_SEVERITY: medium
    SCANSUITE_MIN_CONFIDENCE: reachable
    SCANSUITE_FAIL_ON_SECRETS: all
    SCANSUITE_EXTRA_ARGS: --report-zip scansuite-report.zip
  artifacts:
    paths: [scansuite-report.zip, scansuite.json]
  rules:
    - if: $CI_COMMIT_TAG

# Monorepo: one product per service, in parallel, changed-only.
scansuite-services:
  extends: .scansuite
  parallel:
    matrix:
      - SERVICE: [payments, web]
  variables:
    SCANSUITE_PRODUCT: $SERVICE
    SCANSUITE_PROFILE: quick
    SCANSUITE_CHANGED_ONLY: "1"
    SCANSUITE_EXTRA_ARGS: --source-dir services/$SERVICE
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

## 3. Without the template — run the image yourself

Clear the entrypoint (GitLab runs its own shell). Pass any flags you like.

```yaml
scansuite:
  stage: test
  image:
    name: appsec4u/scansuite-ci:1
    entrypoint: [""]
  variables:
    GIT_DEPTH: "50"        # --changed-only needs the target branch
  script:
    - scansuite-ci --profile quick --changed-only
        --block-class sql_injection --fail-on-severity high
        --junit scansuite-junit.xml --sarif scansuite.sarif
  artifacts:
    when: always
    reports: { junit: scansuite-junit.xml }
    paths: [scansuite.sarif]
```

## 4. Report-only rollout — never fail the pipeline

```yaml
scansuite-report-only:
  extends: .scansuite
  variables:
    SCANSUITE_FAIL_ON_SEVERITY: none
    SCANSUITE_FAIL_ON_SECRETS: none
```

## 5. Large repository — server-side clone, incremental

Nothing is uploaded from the runner; the server clones over SSH and scans only what
changed since the last scan of the branch.

```yaml
scansuite-incremental:
  stage: test
  image: { name: appsec4u/scansuite-ci:1, entrypoint: [""] }
  script:
    - scansuite-ci --source git --mode incremental --profile standard --summary-json scansuite.json
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

## 6. Private CA — verify the server certificate

Commit your CA to the repo (or fetch it in `before_script`) and point the client at it.

```yaml
scansuite:
  extends: .scansuite
  variables:
    SCANSUITE_CA_BUNDLE: ci/corp-root.pem
    # or, to refuse any untrusted certificate instead of warning:
    # SCANSUITE_STRICT_TLS: "1"
```
