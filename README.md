# claude-config

One opinionated Claude Code setup (`~/.claude`) for Windows (Git Bash), macOS and Linux: global rules, hooks that enforce them, skills, agents, small mods and a status line.

The core idea is a ratchet: a repeated correction moves from a chat message to a dated `CLAUDE.md` rule to a hook that blocks the mistake, so `CLAUDE.md` stays short and the rules hold.

## Install

Install Claude Code but don't start it yet. Its installer already creates `~/.claude`, so a plain `git clone` into it fails; fetch into the folder instead. Same three commands on Windows (Git Bash), macOS and Linux:

```bash
mkdir -p ~/.claude && git -C ~/.claude init -b main && git -C ~/.claude remote add origin https://github.com/RoyAbra27/claude-config && git -C ~/.claude pull origin main && git -C ~/.claude branch -u origin/main
claude   # log in once, then quit
bash ~/.claude/bootstrap.sh
```

`bootstrap.sh` installs the CLI tools (winget on Windows, Homebrew on macOS, apt or dnf on Linux; `--dry-run` shows the plan first), asks which third-party skills you want, and is safe to rerun. The setup starts in auto mode (`defaultMode` in `settings.json`); change it before the first start if you want permission prompts.

## What you get

| Part | What it does for you |
|---|---|
| Hooks (`hooks/`) | `guard.sh` blocks destructive commands, secret leaks and risky edits before they run. `plan-redteam-gate.sh` makes a plan survive an attack before you build it. `costly_loop.py` stops blind retry loops. `session-context.sh` starts every session with your branch and the skill router. `lint-on-save.sh` runs the project's own prettier and eslint |
| Skills (`skills/`) | Process on demand: `plan-redteam`, `consult`, `debugging-protocol`, `branch-audit`, `buy-vs-build`, `testing-workflow`, `subagent-dispatch`, `parallel-ticket-delivery` and more. `hooks/skill-router.md` maps situations to them |
| Agents (`agents/`) | Scoped workers: `builder` implements one brief and reports a checkable result, `explore-cheap` searches code cheaply, plus research, critic and consult agents |
| Commands (`commands/`) | `/save-session`, `/resume-session`, `/reflect` carry state across sessions and turn mistakes into proposed fixes |
| Mods (`mods/`) | Small plugins: `/ready` (push checklist), `/shot` (before/after screenshots), `/ratchet` (correction counter), `proof` (warns on untested changes), `compaction-insurance` (saves state before compaction) |
| Status line (`ccline/`) | A ccline status line for the main session and subagents. It prints nothing if ccline isn't installed |

## Make it yours

- Fork it and edit anything. Rules you don't share (for example em-dash and `Co-Authored-By` blocking in `guard.sh`) are plain checks you can delete.
- Machine-specific rules go in `personal.md`: `CLAUDE.md` imports it with `@personal.md`, it is untracked, and a missing file is harmless. Copy `personal.example.md` to start.
- Describe your own stack in `autoMode.environment` in `settings.json`, and review `defaultMode` and the allow/deny rules.
- Try a mod edit locally with `claude --plugin-dir mods/<x>`.
- Pull upstream changes with `bash update.sh`.
- `CLAUDE.md` assumes `jq` (required by the hooks), Python 3, `uv` and `markitdown`; bootstrap installs them.

## Measure it

`bash scripts/ab-setup.sh` compares your setup to vanilla Claude Code on the same tasks. The owner's 2026-11-25 result: the same pass rate on small tasks, about 45% more tokens, and the preferences enforced.

## Credits

These third-party skills are not included in this repo. `scripts/install-skills.sh` (which `bootstrap.sh` runs) installs the ones you pick from upstream:

| Skill | Upstream | License |
|---|---|---|
| archify | [tt-a1i/archify](https://github.com/tt-a1i/archify) | Apache-2.0 |
| impeccable (+ its agents) | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | Apache-2.0 |
| unslop | [heydamir/unslop](https://github.com/heydamir/unslop) by Damir Sokolovsky | CC-BY-4.0 |
| security-audit | [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) | MIT |
| codebase-design, improve-codebase-architecture, to-tickets, wizard | [mattpocock/skills](https://github.com/mattpocock/skills) | MIT |
| android-material3-design-system, android-viewsystem-foundations | [krutikJain/android-agent-skills](https://github.com/krutikJain/android-agent-skills) | MIT |

Plugins: [superpowers](https://github.com/obra/superpowers), [ponytail](https://github.com/DietrichGebert/ponytail), [claude-hud](https://github.com/jarrodwatts/claude-hud), [hyperframes](https://github.com/heygen-com/hyperframes) and the official Claude plugins. The git guardrails in `guard.sh` and some of the testing ideas are adapted from mattpocock/skills.

## License

MIT for everything in this repo. Third-party skills keep their own licenses.
