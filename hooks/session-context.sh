#!/usr/bin/env bash
# SessionStart(startup|resume|clear|compact|fork): the context block below is injected into
# Claude's context, restoring working state that a summary drops and a fresh start never had.
# Ground truth from the repo, not from what a session file claims was done.
# Revised 2026-11-18: output is JSON so a due setup review also reaches the user as a
# systemMessage; plain stdout is shown to Claude only, and Claude did not relay it.
INPUT=$(cat)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && cd "$CWD" 2>/dev/null

SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null)

# Added 2026-11-11: setup review reminder, shown on fresh starts in any project. Weekly since
# 2026-11-18 (one marker per ISO week), with a memory prune step.
REVIEW_WEEK="$(date +%G-W%V)"
REVIEW_DUE=""
if [ "$SOURCE" = "startup" ] && [ "$(date +%Y%m%d)" -ge 20261118 ] && [ ! -f "$HOME/.claude/.setup-review-$REVIEW_WEEK-done" ]; then
  REVIEW_DUE=1
fi

context() {
  echo "## Working state from the repo (session start: $SOURCE)"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "- Branch: $(git branch --show-current 2>/dev/null)"
    echo "- Recent commits:"
    git log --oneline -5 2>/dev/null | sed 's/^/    /'
    CHANGES=$(git status --short 2>/dev/null | head -20)
    if [ -n "$CHANGES" ]; then
      echo "- Uncommitted changes:"
      printf '%s\n' "$CHANGES" | sed 's/^/    /'
    fi
  fi

  # Added 2026-11-24: steps that usually take 30s+ in this repo, learned by costly_loop.py from real durations.
  PY=$(command -v python || command -v python3)
  if [ -n "$CWD" ] && [ -n "$PY" ]; then
    SLOW=$("$PY" "$HOOK_DIR/costly_loop.py" --slow-list "$CWD" 2>/dev/null)
    [ -n "$SLOW" ] && echo "- $SLOW"
  fi

  if [ -n "$REVIEW_DUE" ]; then
    echo "- Weekly setup review is due ($REVIEW_WEEK). Raise it in your first reply, before new work: (1) check skillUsage in ~/.claude.json for subagent-dispatch and debugging-protocol; at 0 uses, move their key lines into CLAUDE.md; (2) run /doctor; (3) ask for the list of things Claude got wrong this week; (4) memory prune pass on the current project's memory dir: propose merges, stale facts and duplicates of CLAUDE.md, apply only what the user approves. When done: touch ~/.claude/.setup-review-$REVIEW_WEEK-done"
  fi

  # Added 2026-09-02: skill/agent router, injected every session start (incl. compact) the
  # same way the superpowers plugin injects using-superpowers. Revised 2026-11-11: no
  # <EXTREMELY_IMPORTANT> wrapper; Claude 5 models over-apply shouted rules (claude.dev
  # context-engineering post, 2026-07-24).
  ROUTER="$HOOK_DIR/skill-router.md"
  if [ -f "$ROUTER" ]; then
    echo
    cat "$ROUTER"
  fi
}

MSG=""
[ -n "$REVIEW_DUE" ] && MSG="Weekly setup review is due ($REVIEW_WEEK): skill usage, /doctor, what Claude got wrong, memory prune."
context | jq -Rs --arg msg "$MSG" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}} + (if $msg != "" then {systemMessage: $msg} else {} end)'
exit 0
