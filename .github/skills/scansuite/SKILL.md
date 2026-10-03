---
name: scansuite
description: 'Run ScanSuite security scans and read their results with the scansuite-ci client and ScanSuite''s API. Covers static analysis of code or a Git repo (SAST, AI SAST, secrets, dependencies, IaC), DAST of web apps, and infrastructure scans (port/network discovery, OSINT/subdomains, Nuclei, OpenVAS, Nessus, image CVEs, AI pentest); chaining them (OSINT a domain, then scan the hosts/ports found); and reading or triaging results (findings, secrets, logs, reports). Use it whenever the user wants to scan code, a repo, a URL, a host/IP range, a domain or a Docker image for vulnerabilities, start or gate a scan in a pipeline using scansuite-ci / appsec4u/scansuite-ci / SCANSUITE_URL, or check and triage what ScanSuite found, even when they only say "scan this" or "is this exploitable" in a ScanSuite project. Do NOT use it to administer the ScanSuite server (e.g. enabling a scanner in settings), to debug CI runner/pipeline plumbing, or to review pasted code or findings without running a scan or querying the server.'
---

# ScanSuite scans for agents

ScanSuite runs the scanners on its own server. The `scansuite-ci` client (a Python
script, or the image `appsec4u/scansuite-ci:1`) uploads code or names targets,
starts the scan, waits, and prints the result; the team API answers everything
else. This skill gives you wrappers for both, the rules that keep a scan safe,
and how to read what comes back.

## Before anything: the rules

These exist because a scan acts on real systems and a token is a credential.

- **The token stays in its file.** It lives in `~/.scansuite-token` (or the file
  `SCANSUITE_TOKEN_FILE` names). The wrappers read it from there; never print it,
  echo it, put it in a command line you show, or copy it elsewhere. If there is
  no token file, ask the user to create one — do not ask them to paste the token
  into the chat.
- **Scan only what the user owns and named.** DAST and infrastructure scans
  touch live systems. Names an OSINT scan turns up are leads, not permission:
  resolve them, drop lookalike domains (dnstwist output is other people's
  domains) and addresses that do not belong to the user, and say what you are
  about to scan before you scan it. The team's target policy also has to allow
  each target, or the client stops with exit code 3.
- **Ask before intrusive or costly scanners.** `hosts_bruter` tries passwords,
  `zap_full` is intrusive, `ai_pentest` behaves like an attacker. AI scanners
  (`mlsast`, `mldast`, `ai_pentest`, `hosts_mlinfra`, the `*-ai` bundles,
  `full-ai` most of all) spend model money. Mention it before a large one.
- **Know the server, team and product.** Use `SCANSUITE_URL`, `SCANSUITE_TEAM` and
  the product the user gives; ask when they did not. A new product can be
  created by the scan itself (`--product-name NAME --create-product`).

## Setup and preflight

The scripts live next to this file; call them by their path (written here as
`scripts/…`). They need `bash`, `curl`, `python3`, and Docker (or set
`SCANSUITE_CLIENT=/path/to/scansuite-ci.py` to run the script without Docker; with
neither, `ssci.sh` downloads the client from the server and checks its SHA-256).

```bash
export SCANSUITE_URL=https://scansuite.example.com SCANSUITE_TEAM=appsec
bash scripts/preflight.sh
```

Preflight prints the client and server versions, the token's role, permissions
and expiry, and every scanner the server offers — with the ones it **cannot**
run for this team and why. Read it before promising a scan: a scanner marked
NOT AVAILABLE (often Nessus, OpenVAS or Snyk) would be refused with exit code 3,
so offer what is available instead and say what the user would have to set up.

On Windows run everything in WSL or Git Bash (with `MSYS_NO_PATHCONV=1` for Docker
paths). With Docker, `ssci.sh` mounts the current directory at `/src`: run it from
the directory to scan, and output files land there.

## Running a scan

`scripts/ssci.sh` is the client with the token wired in; every argument goes to
`scansuite-ci`. For one-off scans turn the quality gate off, so exit code 0 means
"the scan ran", and keep the results in a summary file:

```bash
bash scripts/ssci.sh --product-name my-app --profile standard-ai \
     --fail-on-severity none --fail-on-secrets none --summary-json scan.json
```

Keep a gate (`--fail-on-severity high`, `--max high=0,medium=10`,
`--block-class sql_injection`, `--min-confidence reachable`) only when the user wants
a pass/fail answer. Scans take minutes (quick SAST ~1 min, standard-ai ~3–10, full-ai
or a full-TCP port scan of several hosts longer): run them in the background when
you can and check progress through the API meanwhile.

Pick the scan:

| The user wants | Command (after `ssci.sh --product-name P`) |
|---|---|
| Code in this directory, default depth | `--profile standard-ai` (no AI: `standard-classic`) |
| Fast check of changes | `--profile quick-ai --changed-only --base origin/main` (no AI: `quick-classic`) |
| Everything, nightly | `--profile full-ai` (full Git history needed) |
| A Git repository, cloned by the server | `--source git --git-url URL [--branch B] --profile standard-ai` |
| Only dependencies / secrets / IaC | `--scanners dep_checks --options dep_checks_reachability` · `--scanners secrets --options secrets_ai` · `--scanners iacs_kics --options ""` |
| A web application | `--scan-type dast --target URL --profile quick\|standard\|deep [--header "Authorization: Bearer …"]` |
| Subdomains of a domain | `--scan-type infra --scanners osint --target example.com` (`--options osint_brute` adds guessing) |
| Hosts and open ports | `--scan-type infra --scanners hosts_scan --target IP,IP --ports "All TCP" --no-ping` |
| Vulnerabilities on known ports | `--scan-type infra --scanners nuclei --target IP,IP --ports 22,443,8443 --no-ping` (or `openvas`, `nessus` when available) |
| A container image | `--scan-type infra --scanners docker_image_scan --target registry/image:tag` |

Every option, profile and scanner is in `references/scans.md` — read it for
anything beyond this table.

## Reading the results

```bash
python3 scripts/summarize.py scan.json                 # findings by severity, secrets count (never values)
bash scripts/api.sh -o report.zip GET /scans/123/report
python3 scripts/summarize.py report.zip                # hosts and ports, subdomains, raw scanner results
```

- The client's log names the scan as `Scan abcdefgh (#123)`; the API uses the
  number. `scripts/api.sh GET /scans/123/logs` shows what the server did.
- **Low and Info results are often not stored as findings.** The log then says
  `Stored 0 finding(s) at Medium or above in Vulnerabilities; N below Medium kept
  in the reports only` and the summary shows no findings. The report archive has
  them — summarize it before saying "nothing found".
- Discovery and OSINT scans record **assets**, not findings. Reading them needs
  `asset.read`, which CI-pipeline tokens lack (`Operation is not permitted`): take
  hosts, ports and subdomains from the report archive instead.
- Present results as a short table per scan: what was scanned, how long it took,
  the findings that matter (severity, title, location), and anything that needs
  the user's attention. Do not paste raw JSON.

The team API (products, scans, findings and triage, secrets, logs, reports,
cancel, target policy) is in `references/api.md`, with the permission each call
needs. A CI-pipeline token can scan and read, not triage findings or change
settings; say which permission is missing rather than working around it.

## Chaining scans: recon of a domain

A common request is "find what is exposed for example.com and check it". Do it
in steps, each one feeding the next, and keep the user in the loop between them:

1. **OSINT**: `--scan-type infra --scanners osint --target example.com`. Read the
   subdomains from the report archive (`summarize.py report.zip`).
2. **Resolve and filter**: `python3 scripts/resolve_targets.py names.txt` lists
   what still resolves and the unique addresses. Leave out names that no longer
   resolve, lookalike domains, and addresses the user does not own (shared
   hosting, someone else's cloud address). When in doubt about an address, check
   its TLS certificate or ask.
3. **Discovery**: `--scanners hosts_scan --target IP,IP,… --ports "All TCP" --no-ping`,
   then read open ports per host from the report archive.
4. **Vulnerabilities**: `nuclei` (or `openvas`/`nessus` if preflight shows them
   available) on the same addresses with `--ports` set to the ports found.

## When something goes wrong

| What you see | What it means |
|---|---|
| Exit 3 and a line before it | Configuration: unknown product (`--create-product`?), missing permission, target outside the policy, scanner not set up — the line says which |
| Exit 2, scan `Cancelled` | The scan failed or was stopped; a server restart cancels running scans — check the server is stable, then rerun |
| Exit 1 | The gate blocked (only when a gate is on) |
| Exit 4 / 5 | Timed out (`--timeout`) / server unreachable |
| HTTP 502 while waiting | The server is restarting; the client retries. If the scan then ends Cancelled, rerun it |
| `accepted (Completed)` then `Finished after 0s` | The server returned an earlier scan for the same idempotency key; give `--idempotency-key` a unique value and rerun |
| `N secret(s) could not be verified` | AI verification did not run for them (team AI settings); they are not reported |
| `Shodan API key not found` in an OSINT log | The server has no Shodan key; OSINT still runs with its other sources |
