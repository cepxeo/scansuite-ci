# ScanSuite team API

`bash scripts/api.sh [-o FILE] METHOD PATH [JSON]` — PATH is relative to
`$SCANSUITE_URL/api/teams/$SCANSUITE_TEAM`. Answers are JSON. Lists page with
`limit` and `after` (the answer's `next_after`); scan history pages with
`before` / `next_before`. An HTTP error exits 1 with the status on stderr; a
refused permission answers `{"error": "Operation is not permitted"}`.

## Calls

| Task | Call | Permission |
|---|---|---|
| Who am I, what may I do, when does the token expire | `GET /context` | — |
| Scanners the server can run, and why not | `GET /scanners` | — |
| Find products | `GET "/products?search=shop&limit=50"` | product.read |
| One product | `GET /products/8` | product.read |
| Create a product | `POST /products '{"product_name":"shop","repository_url":"https://git.example/shop"}'` | product.write |
| Rename a product | `PATCH /products/8 '{"product_name":"shop-api"}'` | product.write |
| Scan history | `GET "/scans?product_id=8&status=Finished&scan_type=SAST&limit=20"` | scan.read |
| One scan (status, product, failed scanners) | `GET /scans/123` | scan.read |
| Its log (plain text) | `GET /scans/123/logs` | scan.read |
| Its findings | `GET "/scans/123/findings?severity=Critical&status=Open"` | finding.read |
| Its report archive | `-o report.zip GET /scans/123/report` | report.read |
| Cancel it | `POST /scans/123/cancel` | scan.cancel |
| A job the client started | `GET /jobs/<job_id>` | scan.read |
| Findings across a product | `GET "/findings?product_id=8&status=Open&severity=High&search=sql"` | finding.read |
| One finding | `GET /findings/506` | finding.read |
| Triage a finding | `PATCH /findings/506 '{"status":"False Positive","notes":"test fixture"}'` | finding.write |
| Secrets of a product (detector, location, verification, AI rationale — never the value) | `GET "/secrets?product_id=8&verified=true"` | credential.read |
| Assets (hosts, ports, technologies from discovery and OSINT) | `GET "/assets?product_id=8"` | asset.read |
| Target policy | `GET /settings/targets/dynamic` or `/settings/targets/infra` | scan.target_policy.read |
| Would targets pass the policy? | `POST /settings/targets/dynamic/preview '{"targets":["https://x"]}'` | scan.target_policy.read |
| Audit log | `GET /audit` | audit.read (team members) |

- Finding statuses: `Open`, `In Progress`, `Risk Accepted`, `False Positive`,
  `Resolved`. Severities: `Critical`, `High`, `Medium`, `Low`, `Info`. Gates count
  only Open and In Progress.
- Scans can also be started here (`POST /scans/sast` multipart, `POST
  /scans/dast` or `/scans/infra` JSON), but use the client: it builds the archive,
  checks the selection and permissions, follows the scan and cancels it on
  interrupt.
- The scan's number (`#123` in the client log) is what the API takes; the
  eight-letter reference (`abcdefgh`) is what the console shows.

## What a token can do

A token never exceeds its service account's role. The usual **CI pipeline**
preset has `scan.execute`, `scan.read`, `scan.cancel`, `finding.read`,
`product.read`, `product.write`, `report.read`, `credential.read`: it scans and
reads, but cannot triage findings, read assets, read or change the target
policy, or touch team settings, integrations, the AI provider, members or
tokens. When a task needs one of those, name the missing permission and let the
user do it in the console or issue a token with the *Custom* preset — do not
look for a way around it.

Without `asset.read`, read discovered hosts and ports from the scan's report
archive: `api.sh -o report.zip GET /scans/<id>/report` and
`python3 scripts/summarize.py report.zip`.
