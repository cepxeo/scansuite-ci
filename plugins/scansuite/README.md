# scansuite — ScanSuite agent plugin

A plugin that lets an AI coding agent run ScanSuite scans and read their results
on its own, through the `scansuite-ci` client and the ScanSuite team API. It
bundles one skill (`scansuite`) under [`skills/scansuite/`](skills/scansuite/).

The skill covers static analysis (SAST, AI SAST, secrets, dependencies, IaC),
DAST of web applications, and infrastructure scans (network/port discovery,
OSINT, Nuclei, container-image CVEs, and more), plus listing products, scans,
findings and reports. It carries the safety rules a scan needs — the token stays
in a file, scan only what the user owns, check a scanner is available before
promising it — and wrappers that handle the client, the API, target resolution
and result summaries.

## Install

### Claude Code — as a plugin (recommended)

This repository is a plugin marketplace. In a Claude Code session:

```
/plugin marketplace add cepxeo/scansuite-ci
```
```
/plugin install scansuite@scansuite-ci
```

The skill then triggers on its own when you ask to scan something. Update later
with `/plugin marketplace update scansuite-ci`.

### Claude Code — as loose files

A skill is just a folder with a `SKILL.md`. Copy it where Claude Code looks:

```bash
# personal (all projects), from a clone of this repo
cp -r plugins/scansuite/skills/scansuite ~/.claude/skills/scansuite
# or project-local
cp -r plugins/scansuite/skills/scansuite .claude/skills/scansuite
```

### Claude.ai / Claude desktop app

Upload the skill under **Settings → Customize → Skills**. Zip the skill folder
(so the archive contains `scansuite/SKILL.md`), then **Upload Skill**. It syncs
to your account across claude.ai, the desktop app and Claude Code.

### GitHub Copilot

Copilot's support for the `SKILL.md` format is newer than this doc and evolving
— **verify it against GitHub's current Copilot documentation** before relying on
it. If your Copilot supports it, place the skill at
`.github/skills/scansuite/SKILL.md` in the repo. Regardless, Copilot's
established mechanisms are `.github/copilot-instructions.md` and
`.github/prompts/*.prompt.md`.

## Set up once

The skill reads the API token from a file, never from the chat or a command
line. Create it from a ScanSuite service-account token (Teams page → People →
Automation and API tokens, CI pipeline preset):

```bash
printf '%s' 'YOUR_TOKEN' > ~/.scansuite-token && chmod 600 ~/.scansuite-token
```

Then tell the agent your server and team (or let it ask): `SCANSUITE_URL`,
`SCANSUITE_TEAM`. It needs `bash`, `curl`, `python3`, and either Docker or the
Python client. Ask it to "scan …" and it takes over.
