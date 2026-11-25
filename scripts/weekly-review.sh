#!/usr/bin/env bash
# Weekly read-only setup review (Windows Task Scheduler, Mondays). Writes ~/Desktop/setup-review-<date>.md.
# The data is gathered here and piped in, so the headless session needs only Read/Grep/Glob inside ~/.claude.
set -euo pipefail
cd "$HOME/.claude"
OUT="$HOME/Desktop/setup-review-$(date +%F).md"
NOW_MS=$(( $(date +%s) * 1000 ))

{
  echo "## Skill usage (name, uses, days since last use)"
  jq -r --argjson now "$NOW_MS" '.skillUsage // {} | to_entries | sort_by(-.value.usageCount)[]
    | "\(.key)\t\(.value.usageCount)\t\((($now - (.value.lastUsedAt // 0)) / 86400000) | floor)"' "$HOME/.claude.json"
  echo
  echo "## Installed skills (folders in ~/.claude/skills and enabled plugins)"
  ls -1 skills | grep -v -E '\-workspace$|^synced$'
  jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' settings.json
  echo
  echo "## Session-start text size (characters; tokens ~ chars/4)"
  for f in CLAUDE.md hooks/skill-router.md; do printf '%s\t%s\n' "$f" "$(wc -c < "$f")"; done
  printf 'session-context.sh output\t%s\n' "$(echo '{"source":"startup"}' | bash hooks/session-context.sh 2>/dev/null | wc -c)"
} | claude -p --tools "Read,Grep,Glob" --permission-mode dontAsk "$(cat scripts/weekly-review-prompt.md)" > "$OUT"

echo "wrote $OUT"
