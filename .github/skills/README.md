# `.github/skills/` — Copilot skill location

`scansuite/` here is a **mirror** of the canonical skill at
[`plugins/scansuite/skills/scansuite/`](../../plugins/scansuite/skills/scansuite/),
placed at the path GitHub Copilot reads skills from. Copilot can only load
skills from `.github/skills/`, so this directory holds a real copy rather than a
reference.

**Keep it in sync.** When you change the skill, edit the canonical copy under
`plugins/scansuite/` and refresh this mirror:

```bash
rm -rf .github/skills/scansuite
cp -r plugins/scansuite/skills/scansuite .github/skills/scansuite
```

**Verify Copilot support first.** GitHub Copilot's adoption of the Anthropic
`SKILL.md` format is newer than this repo and not yet confirmed against GitHub's
own documentation here. Check the current Copilot docs for whether
`.github/skills/<name>/SKILL.md` is read in your Copilot version. If it is not,
this mirror is simply unused; Copilot's established, definitely-supported
mechanisms are `.github/copilot-instructions.md` and `.github/prompts/*.prompt.md`.

For Claude Code and Claude.ai, install from the plugin marketplace instead — see
[`plugins/scansuite/README.md`](../../plugins/scansuite/README.md).
