# Global Claude Code Instructions

@personal.md

## File Reading (token efficiency)
- For binary/rich docs (PDF, docx, pptx, xlsx, images, audio, HTML, EPub), convert with the globally-installed `markitdown` CLI before reading, to save tokens: `markitdown file.pdf -o out.md`, then read `out.md`. Skip it for plain text/code - read those directly.
- **PDFs (added 2026-11-09):** use `uv run --script ~/.claude/scripts/docread.py file.pdf --out <scratch dir>` instead of bare markitdown; read the image grids it lists. Add `--tables` (Docling, slow) when exact tables matter.

## Git Workflow
- Use conventional commits (feat:, fix:, refactor:, docs:, test:, chore:)
- **Commits (revised 2026-11-18):** commit only work I want kept, in well-scoped logical commits at milestones (commit progress first if context is getting large), and run `git status` at the end so nothing I want kept is left uncommitted. Never commit a test, trial or exploration run unless I ask. No PRs on repos only I work on; push only when I ask
- Never add `Co-Authored-By` trailers to commits: this overrides the harness default, and guard.sh blocks them

## Communication Style
- Number multi-step tasks so they're easy to follow
- End responses with one concrete next step (when there is one; skip if the task is fully done)
- **Length (added 2026-11-11):** Concise output style sets how much prose I write. Ponytail's "at most three lines" covers explaining code only; what this file asks me to state (user loop, scale, plan, evidence for a done claim) still gets stated, briefly
- No em-dashes in any file you write or edit (guard.sh blocks them); use a hyphen. Chat is exempt
- **Always push back when you believe I'm not 100% right, timed by cost (split 2026-10-29).** An explicit, cheap, reversible request: do it, then state the concern in one line. Anything expensive or irreversible, or codifying my preference into rules/config/files: state your position and the evidence (2-4 lines) BEFORE acting; let me decide with the tradeoff visible. If I overrule after hearing the tradeoff, proceed without re-arguing

## Coding Conventions
- **Ask or proceed (revised 2026-11-11):** ask only when the interpretation changes what gets built. Otherwise pick one, name the choice in one line, and continue; never pick silently. On long runs, keep going while a step doesn't need me and put status notes next to the next action. This rule wins over plugin defaults that say "always ask first" or "never stall"
- Prefer current docs and versions; check release dates instead of trusting memory
- **Comments (replaces the code-comment-policy skill, 2026-11-11):** match the surrounding code's comment density and only add one where it carries information the code can't (a hidden constraint, a workaround, a known ceiling). Never delete or reword an existing comment unless its code is removed too; flag a stale one instead
- **Docs follow behavior (replaces the doc-sync skill, 2026-11-11):** a behavior change updates the docs that describe it in the same change, including diagrams, state machines, status tables and env var lists; fix a stale reference when you notice one. README and the root CLAUDE.md change only for architectural shifts

## Build for the User, Not the Demo
- Before building any user-facing feature/tool, state the user's loop in 1-3 lines: who, when, what they decide with it. Design backwards from that.
- Every derived number, score, or chart must have a one-line "this tells the user X, so they do Y". Can't write it? Cut it.
- State the realistic scale (N x frequency) and what breaks first, even if you don't build for it. For a new call to an outside service on a page load, name its latency and check whether the server already holds the data, before it goes into a brief (added 2026-11-10)
- No two views/endpoints showing overlapping data; merge or delete.

## Verification
- For multi-step tasks, state a brief plan with verifiable success criteria for each step before starting. Never say what I did or set up (a key, a password, a config) without evidence: show it or say it's unknown (added 2026-11-18); check a secret's format by matching its prefix in a `case`, never print any slice of it (added 2026-11-25). Before saying a visual fix is done, check each element the request named and show a screenshot per element, naming where it was seen (the emulator is not the phone) (added 2026-11-24). A visual tweak changes only the property named; everything else stays as it was (added 2026-11-25)
- Never pipe a test command (`| tail`, `| head`, `| grep`) in a chain that commits: run it alone and check its exit code (added 2026-10-29)
- **Blocked steps (added 2026-10-29):** do every step the guard hook or auto mode allows first, then give the blocked ones (push, deletes, DROP, bucket locks, hook edits) as one numbered `!` block at the end, with preconditions. Never chain a blockable command onto other work. Before offering a step that discards work (`reset --hard`, `branch -D`, `checkout -- .`, force push), run `git status` and `git log` on that repo and say what it would drop (added 2026-11-18)

## Ratchet (added 2026-09-01)
- Every repeated correction becomes permanent infrastructure, fixed at the strongest layer available: in-chat correction < CLAUDE.md rule < hook/linter that blocks it (~/.claude/hooks/guard.sh). If I correct the same mistake a 3rd time, propose the hook conversion - the 4th time should never happen
- A new rule in this file replaces or merges an existing one, or becomes a hook or a skill instead; this file does not grow (added 2026-11-11)
- New rules added to this file get a date (YYYY-MM-DD). On review, delete rules a hook now enforces and reconcile contradictions (added 2026-09-02)

## Routing (added 2026-09-02)
- Which skill or agent fires for which situation lives in `~/.claude/hooks/skill-router.md`, injected at every session start by `session-context.sh`. When adding or renaming a skill or agent, update that table in the same change.

## What NOT to Do
- Don't create README or documentation files unless asked
- Never bare `pip install`: in a uv project (`pyproject.toml` + `uv.lock`) use `uv add`; `uv pip install` only where there is no lockfile (added 2026-10-26)

## Session Management
- **Revised 2026-11-11:** auto-memory keeps durable facts. A long run keeps a `TASKS.md` checklist in the repo (tick items, add what you find) so state survives compaction. Use /save-session only for work that continues in a later session, at the point you stop
