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
LONG=$(jq -n --arg p "$(printf '# P\nred-team: skip - tiny\n'; for i in $(seq 1 29); do echo "- step $i"; done)" '{tool_name: "ExitPlanMode", tool_input: {plan: $p}}')
hook 2 plan-redteam-gate.sh "$LONG"
err=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/x/docs/superpowers/plans/p.md"}}' | bash "$DIR/plan-redteam-gate.sh")
printf '%s' "$err" | grep -q '30 non-blank lines or fewer' || { echo "FAIL plan reminder omits the skip limit: $err"; FAIL=1; }
hook 0 no-questions.sh '{"tool_name":"AskUserQuestion","tool_input":{"questions":[]}}'
hook 0 no-questions.sh '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}'
hook 0 lint-on-save.sh '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.md"}}'
hook 0 session-context.sh '{"hook_event_name":"SessionStart","source":"startup"}'

# settings.json: repo hooks run through bash (file mode is irrelevant), and every repo hook
# command plus the status line starts on this OS (not 126/127) when run verbatim
S="$DIR/../settings.json"
CLT=$(mktemp -d)
export CL_STATE="$CLT/state" CL_LOG="$CLT/log.jsonl" CL_DURATIONS="$CLT/dur"
while IFS= read -r cmd; do
  case "$cmd" in *skills/impeccable*) continue ;; esac
  case "$cmd" in
    */.claude/hooks/*.sh*)
      case "$cmd" in *'bash "$HOME/.claude/hooks/'*) ;; *) echo "FAIL settings hook not run via bash: $cmd"; FAIL=1 ;; esac ;;
  esac
  printf '{}' | sh -c "$cmd" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then echo "FAIL settings command cannot start (exit $rc): $cmd"; FAIL=1; fi
done < <(jq -r '(.hooks[][].hooks[].command), .statusLine.command' "$S")

# costly_loop command with no python on PATH exits 0 quietly
mkdir -p "$CLT/bin"
printf '#!%s\nexec %s "$@"\n' "$BASH" "$BASH" > "$CLT/bin/bash"; chmod +x "$CLT/bin/bash"
cmd=$(jq -r '[.hooks[][].hooks[].command | select(test("costly_loop"))][0]' "$S")
err=$(printf '{}' | PATH="$CLT/bin" "$BASH" -c "$cmd" 2>&1 >/dev/null); rc=$?
if [ "$rc" -ne 0 ] || [ -n "$err" ]; then echo "FAIL costly_loop without python (exit $rc): $err"; FAIL=1; fi
unset CL_STATE CL_LOG CL_DURATIONS

# loop-metrics stamps its report with the code that produced it (no transcripts: exit 1 is fine)
PY=$(command -v python || command -v python3)
HOME="$CLT" USERPROFILE="$CLT" "$PY" "$DIR/../scripts/loop-metrics.py" --since 2026-11-24 --until 2026-11-24 --out "$CLT/r.json" >/dev/null 2>&1
jq -e '.script.gate_version and (.script | has("head") and has("argv"))' "$CLT/r.json" >/dev/null 2>&1 \
  || { echo "FAIL loop-metrics report has no script stamp"; FAIL=1; }
find "$CLT" -type f -delete; find "$CLT" -depth -type d -exec rmdir {} \;

# install-skills.sh marks unslop user-invoke-only without touching the rest of the file, once
T=$(mktemp -d)
mkdir -p "$T/unslop"
printf -- '---\nname: unslop\ndescription: x\n---\nbody name: stays\n' > "$T/unslop/SKILL.md"
# --select 3 is unslop; its SKILL.md already exists, so nothing installs and only the patch runs (twice)
SKILLS_DIR="$T" bash "$DIR/../scripts/install-skills.sh" --select 3 >/dev/null 2>&1
SKILLS_DIR="$T" bash "$DIR/../scripts/install-skills.sh" --select 3 >/dev/null 2>&1
if [ "$(sed -n 2p "$T/unslop/SKILL.md")" != "disable-model-invocation: true" ] \
   || [ "$(grep -c '^disable-model-invocation:' "$T/unslop/SKILL.md")" -ne 1 ] \
   || [ "$(grep -c '^name: unslop$' "$T/unslop/SKILL.md")" -ne 1 ] \
   || ! grep -q '^body name: stays$' "$T/unslop/SKILL.md"; then
  echo "FAIL install-skills.sh frontmatter patch:"; cat "$T/unslop/SKILL.md"; FAIL=1
fi
find "$T" -type f -delete; find "$T" -depth -type d -exec rmdir {} \;

[ "$FAIL" -eq 0 ] && echo "smoke: all cases pass"
exit "$FAIL"
