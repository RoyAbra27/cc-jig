# claude-config

My Claude Code setup (`~/.claude`): global rules, custom skills and agents, and the hooks that enforce them. On Windows 11 a new machine is set up with one clone, one login and one script.

It's built for backend work (NestJS/TypeScript, Python, infra), but most of it isn't tied to a stack.

## The idea: rules that ratchet

Most Claude setups pile rules up in `CLAUDE.md` until the model starts ignoring them. This one gives every correction a path to a stronger layer:

```
in-chat correction  ->  CLAUDE.md rule (dated)  ->  hook that blocks it
```

- **Repeated mistakes harden.** On the 3rd correction for the same thing, it gets proposed as a hook in `hooks/guard.sh`. Hooks run before permission checks, so they hold in any mode.
- **Rules carry dates.** On review, rules that a hook now enforces get deleted, so `CLAUDE.md` stays short.
- **A router decides which skill fires.** `hooks/skill-router.md` maps situations to skills and agents. It's injected at every session start, so routing doesn't rely on the model remembering skill descriptions.
- **Subagent output is a hypothesis.** Agents return fixed-field findings (`{claim, file:line, evidence, confidence}`), and the main thread verifies the evidence before acting on it. A `builder` agent's work is accepted only after the main thread reruns the brief's `Done when:` check itself.
- **You talk to one coordinator.** When subagents do the work, the main session doesn't narrate them. It interrupts only for a decision only you can make, logs its own judgment calls, and ends with one report in attention order: decisions, then failures, then finished PRs. Plans meant for delegation answer every owner decision up front, so the run doesn't stall midway.
- **Sessions end with a reflection.** `/reflect` reviews the session's corrections and failed attempts and proposes the smallest fix at the right layer: a skill line, a memory entry, a CLAUDE.md rule or a hook. Nothing gets applied until you approve it.

## How a task flows

The router picks these automatically. You mostly answer questions and read one report at the end.

1. **Idea to spec:** `superpowers:brainstorming` asks the questions, and `consult` argues both sides of any expensive fork.
2. **Spec to plan:** the plan opens with the owner decisions you answer up front, and every task lists its files, its dependencies and a `Done when:` command.
3. **Plan review:** `plan-redteam` attacks the plan before anything runs, and `plan-redteam-gate.sh` won't let plan mode exit without that pass.
4. **Execution:** sequential tasks run under `superpowers:subagent-driven-development`, and waves of file-disjoint tasks run through `parallel-ticket-delivery`. The main session acts as the only coordinator and reruns every check itself.
5. **Before merge:** `branch-audit` for big or sensitive branches, `/code-review` for small diffs.
6. **Session end:** `/save-session` writes the state for next time and runs `/reflect`, which turns the session's mistakes into proposed rule or skill fixes.

## What's inside

```
CLAUDE.md          global instructions: environment quirks, git, communication, coding conventions, verification, ratchet, routing, rtk usage
settings.json      hooks, env, auto-mode allow/deny rules, plugins, status line
hooks/             guard, gates and session context (see below)
skills/            custom skills
agents/            custom subagents
commands/          slash commands: /save-session, /resume-session, /reflect
scripts/install-skills.sh  pick and install the third-party skills (all / none / 1,2,5)
scripts/docread.py document-to-Markdown reader; flags PDF pages with a broken text layer and renders them as image grids
scripts/loop-metrics.py  before/after numbers for the costly-loop gate, from your own transcripts (counts only)
dotfiles/          PowerShell profile + oh-my-posh theme
bootstrap.sh       new-machine setup
```

### Hooks

| Hook | When | What it does |
|---|---|---|
| [`guard.sh`](hooks/guard.sh) | before Edit, Write, Bash, PowerShell | Blocks `rm -rf` (except SDD scratch under `.superpowers/sdd/`), force-push, `reset --hard` and other work-destroying git commands, `DROP`/`TRUNCATE`, bot attribution trailers, secret-shaped strings in commits, edits to secrets files, lockfiles and `.git/` internals, em-dashes in written files (the session scratchpad is exempt), and heredocs fed to python/node that contain a backslash (Git Bash mangles them). Blocks everything if `jq` is missing rather than failing open. Tests: `bash hooks/guard.test.sh` |
| [`plan-redteam-gate.sh`](hooks/plan-redteam-gate.sh) | before ExitPlanMode; after Edit, Write | Blocks leaving plan mode until the plan has had a red-team pass (or an explicit, reasoned opt-out). After an edit to a `docs/superpowers/plans/` or `specs/` file, it reminds Claude to red-team it first |
| [`session-context.sh`](hooks/session-context.sh) | session start, resume, clear, compact, fork | Injects working state from the repo itself (branch, uncommitted files, recent commits) plus the skill router. When the weekly setup review is due, also shows the user a one-line notice |
| [`no-questions.sh`](hooks/no-questions.sh) | each prompt; before AskUserQuestion | A prompt saying "don't ask questions" (English or Hebrew) flags the session, and AskUserQuestion is then denied so Claude decides and names its choice. "you can ask" clears it |
| [`lint-on-save.sh`](hooks/lint-on-save.sh) | after Edit, Write | Runs the project's own prettier and eslint on TS/JS files. Never blocks |
| [`costly_loop.py`](hooks/costly_loop.py) | before Bash, Read, Grep, Glob; after Bash | Stops trial-and-error loops: the second blind rerun in a row of a device install or a slow (60s+) step is blocked until Claude reads or greps something, or states what it expects (`# expect:`); a full video render needs `# final`. It also learns how long each step takes per repo, lists the slow ones at session start, and sends a known-slow foreground step back to run in the background (`# fg` opts out). Together with `BASH_*_TIMEOUT_MS=90000` in `settings.json`, long commands stop blocking the conversation. Python; fails open; `CL_DISABLE=1` turns it off. Tests: `bash hooks/costly_loop.test.sh` |

`settings.json` also wires Impeccable's own hook (after Edit/Write, at session start, at stop). It no-ops when Impeccable isn't installed.

### Commands

| Command | What it does |
|---|---|
| [`/save-session`](commands/save-session.md) | Writes the goal, what's done and verified, what failed, what couldn't run, and what's next to `~/.claude/sessions/` when you stop, and runs `/reflect` |
| [`/resume-session`](commands/resume-session.md) | Reads a saved session file, summarizes it, and confirms the plan before continuing |
| [`/reflect`](commands/reflect.md) | Lists what went wrong this session, with evidence, and proposes the smallest fix at the right layer. Applies only what you approve |

### Skills

| Skill | Use it when |
|---|---|
| [`plan-redteam`](skills/plan-redteam/SKILL.md) | A spec or plan is done. A fresh agent attacks it with evidence, you defend or concede, and you get an agreed change list |
| [`consult`](skills/consult/SKILL.md) | Choosing between options on something expensive or hard to reverse. Context-free agents argue the sides: one agent covers both for a light check, two (one per side) for a real fork |
| [`debugging-protocol`](skills/debugging-protocol/SKILL.md) | A bug or failing test. Scales the process by risk: a repro gate, a ranked hypothesis ledger and a two-attempt loop bound |
| [`subagent-dispatch`](skills/subagent-dispatch/SKILL.md) | Before delegating to any agent. Covers which model, how to write the brief, fixed-field returns, coordinator mode and plans written for delegation |
| [`branch-audit`](skills/branch-audit/SKILL.md) | A big branch is about to ship. Parallel reviewer lanes (API surface, data path, conformance, deploy, client contract, privacy, omissions) feed one consolidated, verified list. Lane yield is tracked over time so weak lanes get cut |
| [`buy-vs-build`](skills/buy-vs-build/SKILL.md) | You're about to hand-roll a queue, retry, cache, parser, auth or rate limiter. It checks installed deps first, then searches the web |
| [`testing-workflow`](skills/testing-workflow/SKILL.md) | Any behavior change: spec first, a failing repro test before a bug fix |
| [`prompt-shake`](skills/prompt-shake/SKILL.md) | After editing a prompt file (CLAUDE.md, a skill, an agent). Tightens it so rules don't only grow |
| [`frontend-flow`](skills/frontend-flow/SKILL.md) | UI work. Chains Impeccable, unslop and the Android skills instead of picking one |
| [`parallel-ticket-delivery`](skills/parallel-ticket-delivery/SKILL.md) | Several independent tickets, each shipped as its own PR by a parallel worktree agent. It proves file-disjointness first, writes one shared brief, reruns every agent's check, and reports to you only when a decision is needed |
| [`backend-api`](skills/backend-api/SKILL.md) | Build-time decisions for endpoints, jobs and migrations in any framework (auth per route, idempotency, backward-compatible migrations, timeouts), with framework facts from current docs and a NestJS gotchas file |

### Agents

| Agent | Role |
|---|---|
| [`builder`](agents/builder.md) | Implements one scoped change from a brief, runs its check, and reports in a fixed format (status, files, command, exit code, output) |
| [`explore-cheap`](agents/explore-cheap.md) | Low-cost read-only codebase search that returns `file:line` answers, not file dumps |
| [`library-scout`](agents/library-scout.md) | The outward research lane for `buy-vs-build`: verified candidates, never a verdict |
| [`consult-side`](agents/consult-side.md) | Argues one side of a `consult` from a frozen brief |
| [`plan-redteam-lead`](agents/plan-redteam-lead.md) | The skeptical team lead for `plan-redteam` |
| [`product-dreamer`](agents/product-dreamer.md) | Product-vision research: ranked feature ideas, each with cited evidence, user moment, trust risk, cost and effort, plus patterns to steal and anti-patterns |
| [`hebrew-copywriter`](agents/hebrew-copywriter.md) | Native Israeli Hebrew for any medium (UI, video, decks, marketing, email, social, docs): rewrites translated-sounding drafts, keeps terms consistent, handles gendered address and mixed-direction text |

## Install

On Windows 11 with Git Bash, or macOS (see below). Install Claude Code but don't start it yet (the first start creates `~/.claude`, and the clone needs that folder not to exist). Then:

```bash
git clone https://github.com/RoyAbra27/claude-config ~/.claude
claude   # log in once, then quit
bash ~/.claude/bootstrap.sh
```

The script installs CLI tools (winget, uv), PowerShell modules, the dotfiles, the user-scope mobile MCP server and the [`agent-browser`](https://github.com/vercel-labs/agent-browser) CLI for headless browser checks. Zed is installed as `$EDITOR`; swap it in `settings.json` if you use something else. It then shows a numbered menu of the third-party skills listed below and asks which to install: `all`, `none` or a list like `1,2,5`. To skip the prompt, pass `--skills all|none|1,2,5`. To add skills later, run `bash ~/.claude/scripts/install-skills.sh` (add `--dry-run` to preview). It's safe to rerun: installed items are skipped, overwritten dotfiles get a `.bak-<timestamp>` copy, and anything that fails is listed at the end. Plugins in `settings.json` download on the first `claude` start.

Already have a `~/.claude`? Don't clone over it. Copy the pieces you want instead: `hooks/guard.sh` and its `settings.json` entry work on their own.

On macOS, install [Homebrew](https://brew.sh) and run the same `bash ~/.claude/bootstrap.sh`: it installs the tools with Homebrew instead of winget and skips the PowerShell modules and dotfiles. On Linux it checks for the tools instead of installing them. The hooks are bash, except `costly_loop.py` (Python 3), and CI runs `hooks/guard.test.sh`, `hooks/smoke.test.sh` and `hooks/costly_loop.test.sh` on macOS and Linux on every push. `CLAUDE.md`'s Environment section and the weekly setup-review reminder in `hooks/session-context.sh` are specific to my machine; delete them on yours.

### Make it yours

- `guard.sh` enforces my preferences too: it blocks em-dashes in written files and `Co-Authored-By` trailers in commits. Delete those two checks if you don't share them.
- `plan-redteam-gate.sh` blocks leaving plan mode until the plan has a red-team pass (or a `red-team: skip - <reason>` line). Remove its two entries in `settings.json` if that's too strict for you.
- The router (`hooks/skill-router.md`) names third-party skills. Rows for skills you didn't install simply don't apply.
- `costly_loop.py` blocks and bounces some of Claude's commands (see Hooks). If that's not for you, remove its three entries in `settings.json` and the two `BASH_*_TIMEOUT_MS` lines, or set `CL_DISABLE=1` in `env`.
- `CLAUDE.md` assumes some CLIs: `jq` (required by the hooks), Python 3 (for `costly_loop.py`; without it the hook exits quietly), `uv`, `markitdown` and [`rtk`](https://github.com/rtk-ai/rtk) for compact command output (bootstrap installs all of these; `settings.json` sets `RTK_SUPPRESS_HOOK_WARNING=1` because rtk is used manually, without its hook).
- `CLAUDE.md` has an Environment section with Windows-specific rules (PowerShell profile path, Git Bash quirks). Rewrite it for your machine first.
- `settings.json` sets `"defaultMode": "auto"` and my auto-mode allow and deny rules. Review them before you use the setup.
- `bootstrap.sh --capture` copies your live PowerShell profile and oh-my-posh config back into `dotfiles/`.

## Updating

The setup changes often. Paste this prompt into Claude Code, run from any folder, and it works out how you installed the setup and updates it without losing your own changes:

````text
Update my Claude Code setup from https://github.com/RoyAbra27/claude-config (branch main) without losing anything I changed. Work step by step and stop to ask me whenever a choice is not obvious.

1. Find out how I installed it, without changing anything yet:
   - Is ~/.claude a git repo? If yes, list its remotes and branch.
   - origin is RoyAbra27/claude-config: a direct clone. My upstream is origin.
   - origin is my own fork: add RoyAbra27/claude-config as a remote named upstream (if missing). My upstream is upstream.
   - Not a git repo, or a clone somewhere else: I copied pieces by hand. Clone the repo to a temp folder instead and go to step 5.
   Tell me which case you found before going on.
2. Save my changes: run git status. If anything is modified or new, show me the list, then commit it on my branch as "local: <short summary>". Never push it.
3. Show what is new: fetch my upstream, then show git log --oneline HEAD..<upstream>/main and a diff --stat, summarized in plain words.
4. Update: git rebase <upstream>/main. On a conflict, keep the upstream change and re-apply my intent on top of it; if you can't tell what I meant, stop and ask me. Never use reset --hard, never force-push, never delete my commits.
5. Copied pieces only: compare each file I have against the temp clone, show me what changed per file, and update only the files I approve. Keep my edits by merging them in, not by overwriting.
6. If the update touched bootstrap.sh, scripts/install-skills.sh or .gitignore, rerun bash ~/.claude/bootstrap.sh (Windows and macOS; it skips what is already installed and asks which third-party skills I want).
7. Check it works: jq empty ~/.claude/settings.json, then bash ~/.claude/hooks/guard.test.sh, bash ~/.claude/hooks/smoke.test.sh and bash ~/.claude/hooks/costly_loop.test.sh must each print "all cases pass".
8. Report: what is new, which of my changes were kept and where, anything I need to do (usually: restart Claude Code to load new hooks and skills).
````

Your own changes live as `local:` commits on top of upstream, so each update replays them instead of overwriting them.

## Credits

These third-party skills are not included in this repo. `scripts/install-skills.sh` (which `bootstrap.sh` runs) installs the ones you pick from upstream:

| Skill | Upstream | License |
|---|---|---|
| archify | [tt-a1i/archify](https://github.com/tt-a1i/archify) | Apache-2.0 |
| impeccable (+ its agents) | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | Apache-2.0 |
| hallmark | [Nutlope/hallmark](https://github.com/Nutlope/hallmark) | MIT |
| unslop | [heydamir/unslop](https://github.com/heydamir/unslop) by Damir Sokolovsky | CC-BY-4.0 |
| security-audit | [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) | MIT |
| codebase-design, improve-codebase-architecture, to-tickets, wizard | [mattpocock/skills](https://github.com/mattpocock/skills) | MIT |
| android-material3-design-system, android-viewsystem-foundations | [krutikJain/android-agent-skills](https://github.com/krutikJain/android-agent-skills) | MIT |
| developing-with-streamlit | [streamlit/agent-skills](https://github.com/streamlit/agent-skills) (archived, now ships with Streamlit) | Apache-2.0 |

Plugins: [superpowers](https://github.com/obra/superpowers), [ponytail](https://github.com/DietrichGebert/ponytail), [claude-hud](https://github.com/jarrodwatts/claude-hud), [hyperframes](https://github.com/heygen-com/hyperframes) and the official Claude plugins. The git guardrails in `guard.sh` and some of the testing ideas are adapted from mattpocock/skills.

## License

MIT for everything in this repo. Third-party skills keep their own licenses.
