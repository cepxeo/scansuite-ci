# ScanSuite agent skills

Skills that let an AI coding agent run ScanSuite scans and read their results on
its own, through the `scansuite-ci` client and the ScanSuite team API.

## scansuite

Run security scans and work with the results: static analysis (SAST, AI SAST,
secrets, dependencies, IaC), DAST of web applications, and infrastructure scans
(network discovery, OSINT, Nuclei, container images, and more), plus listing
products, scans, findings and reports. The skill carries the safety rules a scan
needs — the token stays in a file, scan only what the user owns, check a scanner
is available before promising it — and wrappers that handle the client, the API,
target resolution and result summaries.

### Install

A skill is a folder with a `SKILL.md`. Copy `scansuite/` to where your agent
looks for skills:

- **Claude Code / Claude**: `~/.claude/skills/scansuite/` (personal) or
  `.claude/skills/scansuite/` in a repository.
- **GitHub Copilot** (agent versions that read skills): `.github/skills/scansuite/`.

```bash
# from a clone of this repository
cp -r skills/scansuite ~/.claude/skills/scansuite
```

### Set up once

The skill reads the API token from a file, never from the chat or a command
line. Create it from a ScanSuite service-account token (Teams page → People →
Automation and API tokens, CI pipeline preset):

```bash
printf '%s' 'YOUR_TOKEN' > ~/.scansuite-token && chmod 600 ~/.scansuite-token
```

Then tell the agent your server and team (or let it ask): `SCANSUITE_URL`,
`SCANSUITE_TEAM`. It needs `bash`, `curl`, `python3`, and either Docker or the
Python client. Ask it to "scan …" and it takes over.
