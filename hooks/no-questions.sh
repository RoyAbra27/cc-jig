#!/usr/bin/env bash
# Added 2026-11-18 (Ratchet: "don't ask questions" corrected 5 times in one week).
# UserPromptSubmit: a prompt saying "don't ask (questions)" flags the session; "you can ask"
# clears the flag. PreToolUse(AskUserQuestion): denied while the session is flagged, so
# Claude decides, names the choice in one line, and continues.
INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-')
[ -z "$SID" ] && exit 0
DIR="$HOME/.claude/.state"
FLAG="$DIR/no-questions-$SID"

case "$EVENT" in
  UserPromptSubmit)
    PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
    # Harness-injected prompts (task notifications, subagent reports) are not the user speaking.
    # Narrowed 2026-11-25: only those tags, not every prompt starting with "<" (a pasted <div> is the user).
    case "$PROMPT" in "<subagent"*|*"<task-notification>"*) exit 0 ;; esac
    if printf '%s' "$PROMPT" | grep -qiE "you can ask|feel free to ask"; then
      rm -f "$FLAG"
    elif printf '%s' "$PROMPT" | grep -qiE "(don'?t|do not|no need to|without) ask(ing)?( me)?( any)?( more)?( questions?)?|no questions|בלי שאלות|אל תשאל"; then
      mkdir -p "$DIR" && touch "$FLAG"
      # Old flags from finished sessions: keep the directory small.
      find "$DIR" -name 'no-questions-*' -mtime +7 -delete 2>/dev/null
    fi
    ;;
  PreToolUse)
    if [ -f "$FLAG" ]; then
      jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
        permissionDecisionReason: "The user said not to ask questions in this session. Pick the most sensible option, name the choice in one line, and continue. A destructive or irreversible step still waits: list it at the end as a blocked step instead of asking."}}'
    fi
    ;;
esac
exit 0
