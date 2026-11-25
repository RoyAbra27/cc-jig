#!/usr/bin/env bash
# Weekly read-only setup review (run by hand, or from cron/launchd/Task Scheduler on Mondays).
# Writes ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/reviews/setup-review-<date>.md.
# The data is gathered here and piped in, so the headless session needs only Read/Grep/Glob inside the config dir.
set -euo pipefail
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cd "$CFG"
mkdir -p reviews
OUT="$CFG/reviews/setup-review-$(date +%F).md"
NOW_MS=$(( $(date +%s) * 1000 ))
# with CLAUDE_CONFIG_DIR set, Claude Code keeps its global state file inside it
STATE_JSON="$CFG/.claude.json"; [ -f "$STATE_JSON" ] || STATE_JSON="$HOME/.claude.json"

{
  echo "## Skill usage (name, uses, days since last use)"
  jq -r --argjson now "$NOW_MS" '.skillUsage // {} | to_entries | sort_by(-.value.usageCount)[]
    | "\(.key)\t\(.value.usageCount)\t\((($now - (.value.lastUsedAt // 0)) / 86400000) | floor)"' "$STATE_JSON"
  echo
  echo "## Installed skills (folders in skills/ and enabled plugins)"
  ls -1 skills | grep -v -E '\-workspace$|^synced$'
  jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' settings.json
  echo
  echo "## Session-start text size (characters; tokens ~ chars/4)"
  for f in CLAUDE.md hooks/skill-router.md; do printf '%s\t%s\n' "$f" "$(wc -c < "$f")"; done
  printf 'session-context.sh output\t%s\n' "$(echo '{"source":"startup"}' | bash hooks/session-context.sh 2>/dev/null | wc -c)"
  echo
  echo "## Trials (name, since, sessions that used it since then; '-' = passive)"
  # local/trials.tsv (untracked, no header) holds your own trials; same columns
  { tail -n +2 scripts/trials.tsv; if [ -f local/trials.tsv ]; then cat local/trials.tsv; fi; } | while IFS=$'\t' read -r name since pat; do
    if [ "$pat" = "-" ]; then n="-"; else
      # ab-fixture- dirs are A/B harness runs, not real sessions
      n=$(find projects -name '*.jsonl' -not -path '*/subagents/*' -not -path '*ab-fixture-*' -newermt "$since" -print0 2>/dev/null | xargs -0 -r grep -l -E -- "$pat" 2>/dev/null | wc -l)
    fi
    printf '%s\t%s\t%s\n' "$name" "$since" "$n"
  done
  if [ -f "$HOME/.claude-mods-data/ratchet.json" ]; then echo; echo "## Ratchet corrections per CLAUDE.md heading"; cat "$HOME/.claude-mods-data/ratchet.json"; fi
} | claude -p --tools "Read,Grep,Glob" --permission-mode dontAsk "$(cat scripts/weekly-review-prompt.md)" > "$OUT"

echo "wrote $OUT"
