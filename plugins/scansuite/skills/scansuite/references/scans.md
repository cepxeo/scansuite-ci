# scansuite-ci options by scan type

All commands are `bash scripts/ssci.sh --product-name P …` (or `--product-id N`;
`--create-product` creates a missing product). `--list-scanners` prints what the
server can run; a scanner it cannot run, or a target outside the team's policy,
stops the client with exit code 3 before a scan starts.

## Contents
- Static analysis (default `--scan-type sast`)
- Web applications (`--scan-type dast`)
- Infrastructure (`--scan-type infra`)
- Waiting, cancelling, outputs
- The quality gate
- Exit codes

## Static analysis

The client archives the files Git tracks in the current directory (or
`--source-dir DIR`) and uploads them.

| `--profile` | Scanners | Typical time |
|---|---|---|
| `quick-classic` | `sast_quick` (Semgrep), `secrets` | ~1 min |
| `standard-classic` | `sast_full`, `secrets`, `dep_checks` | a few minutes |
| `full-classic` | `sast_full`, `sast_quick`, `sast_custom`, `iacs_kics`, `secrets`, `dep_checks` | longer |
| `quick-ai` | `mlsast`, `secrets` + `secrets_ai` | under a minute on small changes |
| `standard-ai` (default) | `mlsast` + `mlsast_reachability`, `secrets` + `secrets_ai`, `dep_checks` + `dep_checks_reachability` | 3–10 min |
| `full-ai` | standard-ai + `mlsast_security_architecture`, `mlsast_boundary_hunt`, `mlsast_git_history` | 7–25+ min |

Old names still work: `quick` = `quick-classic`, `standard` = `standard-ai`,
`deep` = `full-ai`.

- `--changed-only [--base BRANCH]` — only files changed against a branch (merge
  request pipelines give the base themselves). Secrets and dependency checks
  need the whole repository and are skipped in this mode.
- `--mode custom-scope --scope GLOB [--scope GLOB …]` or `--scope-file FILE` —
  selected paths; scanners that cannot be limited to files are left out.
- `--scanners LIST` replaces the profile's scanners, `--add-scanners LIST` adds
  to them, `--options LIST` sets the AI features, `--no-ai-verification` drops
  them. Engines: `mlsast` (AI SAST), `sast_quick`, `sast_full`, `sast_custom`
  (the team's Semgrep rules), `iacs_kics` (IaC), `secrets`, `dep_checks`, `snyk`
  (needs a team Snyk key), and native engines `python` (Bandit), `java`
  (FindSecBugs), `csharp`, `go`, `javascript`, `typescript`, `kotlin`, `php`,
  `ruby`, `swift`, `cpp`.
- `--git-history` adds Git history analysis (needs the full history, not a
  shallow clone); `--lang LANG` sets the main language.
- `--exclude GLOB` leaves paths out; `--no-git-ls-files` archives untracked
  files too; `--max-archive-mb N` caps the upload (default 1024).
- **Let the server clone** instead of uploading: `--source git --git-url URL
  [--branch B] [--repository-url WEB_URL]`. Public HTTPS repositories work as
  they are. Private ones need the team's SSH key for cloning (set by a person in
  the team settings) and an SSH URL (`ssh://git@host:PORT/group/repo.git` for a
  non-standard port); HTTPS URLs must not contain credentials. `--mode
  incremental` then scans only commits since the server's last scan of that
  branch (`Nothing to scan … no new commits` exits 0).

## Web applications

`--scan-type dast --target URL` (repeat `--target` or comma-separate URLs).

| `--profile` | Scanners |
|---|---|
| `quick` | `dast_quick`, `tech_discovery` |
| `standard` (default) | `dast_quick`, `nuclei`, `tech_discovery`, `dirbust` |
| `deep` | `dast_balanced`, `nuclei`, `tech_discovery`, `dirbust`, `mldast` (AI DAST) |

Other scanners: `zap_full` (OWASP ZAP full — intrusive), `api_scan`, `crawl`
(secrets in pages), `nuclei_custom` (the team's Nuclei rules), `ai_pentest`,
`acunetix` and `nessus_web` where the server has them.

- Behind a login: `--header "Authorization: Bearer …"` (several: `"A: 1|B: 2"`)
  or `--cookie "session=…; other=…"`. Keep such values in environment variables,
  not in commands you show.
- `--instructions TEXT` guides `ai_pentest`, for example which areas to focus on
  and what is off limits.

## Infrastructure

`--scan-type infra --scanners LIST --target T[,T…]`. No profiles: name the
scanners. "Runs alone" scanners cannot be combined with others.

| Scanner | What it does |
|---|---|
| `hosts_scan` | Network discovery (nmap): hosts, open ports, services. Runs alone |
| `hosts_prescan` | Live-host discovery before the vulnerability scanners |
| `nuclei`, `nuclei_custom` | Template checks for exposed services; the team's own templates (skipped when no custom rule applies to the product) |
| `openvas`, `nessus` | Full vulnerability scanners, when set up for the team / server |
| `hosts_bruter` | Weak and leaked credentials on known services — ask first |
| `hosts_patching` | Local patching checks over SSH with the team's server account. Runs alone |
| `hosts_mlinfra` | AI infrastructure scan |
| `ai_pentest` | AI pentest; guide it with `--instructions` |
| `osint` (option `osint_brute`) | Subdomains and related domains (subfinder, theHarvester, assetfinder, dnstwist lookalikes). Runs alone |
| `docker_image_scan` | CVEs in a container image, pulled from its registry. Runs alone |

- `--ports` — `All TCP` (default), `Top 1000 TCP/UDP`, or a list such as
  `22,80,443,8443`.
- `--no-ping` — also scan hosts that do not answer ping (most Internet hosts).
- Targets: addresses, ranges (`10.0.4.0/24`), host names, domains (OSINT),
  image references (`docker.io/library/python:3.8-slim`).

## Waiting, cancelling, outputs

- The client polls every 20 s (`--poll-interval`) for up to 2 h (`--timeout`,
  seconds; raise it for big scans). `--cancel-on-timeout` cancels the scan when
  it gives up. Interrupting the client cancels the scan unless
  `--no-cancel-on-interrupt`.
- `--no-wait` starts the scan and exits 0; follow it through the API.
- `--summary-json FILE` (scan, gate, findings, secrets without values),
  `--junit FILE`, `--sarif FILE`, `--report-zip FILE` (full archive),
  `--print-logs-on-failure`, `--max-print N`.
- `--idempotency-key KEY` — a retried start returns the same scan; give a fresh
  key when a new scan must start.
- TLS: `--ca-bundle FILE` for a private CA, `--strict-tls` to refuse unknown
  certificates, `--insecure` to skip verification (testing only).

## The quality gate

Off for exploration (`--fail-on-severity none --fail-on-secrets none`); on when
a pass/fail answer is wanted. Only this scan's findings in status Open or In
Progress count.

| Option | Fails the run when |
|---|---|
| `--fail-on-severity high` | a finding is at or above this severity (default `high`) |
| `--max high=0,medium=10` | a severity's count exceeds its budget |
| `--block-class sql_injection,command_injection` | a finding of these classes appears, at any severity |
| `--min-confidence reachable` | (narrows the above) only AI-confirmed reachable findings, or known exploits, count |
| `--include-unreachable` | (widens) findings AI marked unreachable count too |
| `--fail-on-secrets new\|all\|none` | secrets new to the product (default) / any of the product's / never. The first scan of a new product sees every secret as new |
| `--soft-fail` | scan failures, timeouts and outages exit 0 instead of 2/4/5 |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Passed, or nothing to scan |
| 1 | Gate failed |
| 2 | Scan failed, was cancelled or refused, or a scanner did not complete |
| 3 | Configuration: option, token, permission, product, target, scanner, certificate — the line before says which |
| 4 | Timed out |
| 5 | ScanSuite unreachable |
