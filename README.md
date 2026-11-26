# cc-jig

**A Claude Code harness that turns your corrections into enforced rules.**

A repeated correction moves from chat to a `CLAUDE.md` rule to a hook that blocks it. It lives in `~/.claude` on Windows (Git Bash), macOS and Linux: rules, hooks that enforce them, skills, agents, mods and a status line.

## Install

Needs Claude Code 2.1.324+. Already use Claude Code? Back up first: `mv ~/.claude ~/.claude.bak`.

```bash
mkdir -p ~/.claude && git -C ~/.claude init -b main && { git -C ~/.claude remote add origin https://github.com/RoyAbra27/cc-jig 2>/dev/null || git -C ~/.claude remote set-url origin https://github.com/RoyAbra27/cc-jig; } && git -C ~/.claude pull origin main && git -C ~/.claude branch -u origin/main
claude   # log in once, then quit
bash ~/.claude/bootstrap.sh   # add --dry-run to see the plan first
```

Bootstrap installs the CLI tools, then asks which skills, mods and components you want and your editor. Enter keeps the defaults. It starts in auto mode; set `defaultMode` in `settings.json` before the first start if you want permission prompts.

### Or let your agent take care of it

Paste this into Claude Code:

```text
Install the Claude Code config from https://github.com/RoyAbra27/cc-jig into ~/.claude.
1. Copy ~/.claude to ~/.claude.bak-<date> (copy, don't move: this session runs from it).
2. Follow the README's Install section. If git refuses to overwrite existing files, move only
   those files into the backup and retry.
3. Before running bootstrap.sh, ask me its questions (skills, mods, style checks, components
   to skip, editor; see the usage header in bootstrap.sh) and pass my answers as flags.
4. Tell me what was installed, what failed, and to restart Claude Code.
```

## What you get

| Part | What it does |
|---|---|
| Hooks | `guard.sh` blocks destructive commands, secret leaks and risky edits; `plan-redteam-gate.sh` makes plans survive an attack; `costly_loop.py` stops blind retry loops; `lint-on-save.sh` runs your project's linters |
| Skills | `plan-redteam`, `consult`, `debugging-protocol`, `branch-audit`, `buy-vs-build`, `testing-workflow` and more; `hooks/skill-router.md` says when each fires |
| Agents | `builder`, `explore-cheap`, research, critic and consult agents |
| Commands | `/save-session`, `/resume-session`, `/reflect` |
| Mods | `/ready`, `/shot`, `/ratchet`, `proof`, `compaction-insurance` |
| Status line | ccline, silent if not installed |

## Make it yours

- Update: `bash ~/.claude/update.sh`. Commit your own edits in the clone; updates rebase them.
- Your bootstrap answers live in `local/choices` and are replayed on every update; rerun `bootstrap.sh` with a flag to change one.
- Style checks (on by default): the guard blocks em-dashes and `Co-Authored-By` trailers. Turn them off with `bootstrap.sh --style-checks drop`.
- Machine-specific rules go in the untracked `personal.md` (see `personal.example.md`).
- To remove the guard, delete its entries in `settings.json`, never the file: a missing `guard.sh` blocks every tool call.
- Forks: point `extraKnownMarketplaces.local-mods` in `settings.json` at your fork.

## Uninstall

Delete `~/.claude` and restore your backup. Outside it, bootstrap added the npm packages `agent-browser` and `@cometix/ccline`, the uv tool `markitdown`, the `mobile` MCP server (`claude mcp remove --scope user mobile`) and `~/.claude-mods-data`.

## Contributing

Issues and small PRs welcome. Run the hook tests in `hooks/*.test.sh` with `HOME` pointed at a throwaway folder.

## Credits

Third-party skills are installed from upstream by `scripts/install-skills.sh`, not bundled:

| Skill | Upstream | License |
|---|---|---|
| archify | [tt-a1i/archify](https://github.com/tt-a1i/archify) | Apache-2.0 |
| impeccable (+ its agents) | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | Apache-2.0 |
| unslop | [heydamir/unslop](https://github.com/heydamir/unslop) by Damir Sokolovsky | CC-BY-4.0 |
| security-audit | [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) | MIT |
| codebase-design, improve-codebase-architecture, to-tickets, wizard | [mattpocock/skills](https://github.com/mattpocock/skills) | MIT |
| android-material3-design-system, android-viewsystem-foundations | [krutikJain/android-agent-skills](https://github.com/krutikJain/android-agent-skills) | MIT |

Plugins: [superpowers](https://github.com/obra/superpowers), [ponytail](https://github.com/DietrichGebert/ponytail), [claude-hud](https://github.com/jarrodwatts/claude-hud), [hyperframes](https://github.com/heygen-com/hyperframes) and the official Claude plugins. The git guardrails in `guard.sh` are adapted from mattpocock/skills.

## License

MIT for this repo; third-party skills keep their own licenses.
