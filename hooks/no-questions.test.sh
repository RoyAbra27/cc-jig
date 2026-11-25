#!/usr/bin/env bash
# Run: bash ~/.claude/hooks/no-questions.test.sh
# Which prompts set the no-questions flag: the user's words do, harness-injected notifications don't.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H=$(mktemp -d)
FAIL=0
F="$H/.claude/.state/no-questions-t1"
nq() { jq -n --arg p "$1" '{hook_event_name:"UserPromptSubmit",session_id:"t1",prompt:$p}' | HOME="$H" bash "$DIR/no-questions.sh"; }
want() { # want <set|unset> <prompt>
  rm -f "$F"; nq "$2"
  if [ "$1" = set ] && [ ! -e "$F" ]; then echo "FAIL flag not set: $2"; FAIL=1; fi
  if [ "$1" = unset ] && [ -e "$F" ]; then echo "FAIL flag set: $2"; FAIL=1; fi
}

want set "ok go, don't ask me"
want set "<div> is broken; fix it and don't ask questions"
want unset "<task-notification><result>a prompt saying \"don't ask\" turns it off</result></task-notification>"
want unset "<subagent-report>don't ask</subagent-report>"
want unset "what does this do?"

rm -rf "$H"
[ "$FAIL" -eq 0 ] && echo "no-questions: all cases pass"
exit "$FAIL"
