#!/usr/bin/env bash
# Run: bash ~/.claude/hooks/smoke.test.sh
# Every hook on a sample input, plus the install-skills frontmatter patch. CI runs this on macOS and Linux.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0

hook() {
  local want="$1" name="$2" input="$3" got err
  err=$(printf '%s' "$input" | bash "$DIR/$name" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -ne "$want" ] || printf '%s' "$err" | grep -qiE 'command not found|illegal option|invalid option|unknown option'; then
    echo "FAIL $name (want $want, got $got): $err"
    FAIL=1
  fi
}

hook 2 plan-redteam-gate.sh '{"tool_name":"ExitPlanMode","tool_input":{"plan":"# P\n- a"}}'
hook 0 plan-redteam-gate.sh '{"tool_name":"ExitPlanMode","tool_input":{"plan":"# P\nred-team: skip - tiny\n- a"}}'
hook 0 no-questions.sh '{"tool_name":"AskUserQuestion","tool_input":{"questions":[]}}'
hook 0 no-questions.sh '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}'
hook 0 lint-on-save.sh '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.md"}}'
hook 0 session-context.sh '{"hook_event_name":"SessionStart","source":"startup"}'

# install-skills.sh marks hallmark user-invoke-only without touching the rest of the file
T=$(mktemp -d)
mkdir -p "$T/hallmark"
printf -- '---\nname: hallmark\ndescription: x\n---\nbody name: stays\n' > "$T/hallmark/SKILL.md"
# --select 3 is hallmark; its SKILL.md already exists, so nothing installs and only the patch runs
SKILLS_DIR="$T" bash "$DIR/../scripts/install-skills.sh" --select 3 >/dev/null 2>&1
if [ "$(sed -n 2p "$T/hallmark/SKILL.md")" != "disable-model-invocation: true" ] \
   || [ "$(grep -c '^disable-model-invocation:' "$T/hallmark/SKILL.md")" -ne 1 ] \
   || ! grep -q '^body name: stays$' "$T/hallmark/SKILL.md"; then
  echo "FAIL install-skills.sh frontmatter patch:"; cat "$T/hallmark/SKILL.md"; FAIL=1
fi
find "$T" -type f -delete; find "$T" -depth -type d -exec rmdir {} \;

[ "$FAIL" -eq 0 ] && echo "smoke: all cases pass"
exit "$FAIL"
