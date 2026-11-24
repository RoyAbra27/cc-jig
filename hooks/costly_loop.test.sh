#!/usr/bin/env bash
# Run: bash ~/.claude/hooks/costly_loop.test.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=$(command -v python || command -v python3)
TMP=$(mktemp -d)
export CL_STATE="$TMP/state" CL_LOG="$TMP/log.jsonl" CL_SLOW_MS=60000
FAIL=0
T=1000

# ev <want-exit> <label> <event> <tool> <tool_input-json> [duration_ms]
ev() {
  local want="$1" label="$2" event="$3" tool="$4" inp="$5" dur="${6:-0}" got
  T=$((T + 10))
  jq -n --arg e "$event" --arg t "$tool" --argjson i "$inp" --argjson d "$dur" --arg s "${SID:-s1}" \
    '{hook_event_name: $e, session_id: $s, tool_name: $t, tool_input: $i, duration_ms: $d, tool_use_id: "x"}' \
    | CL_NOW=$T "$PY" "$DIR/costly_loop.py" 2>/dev/null
  got=$?
  if [ "$got" -ne "$want" ]; then echo "FAIL (want $want, got $got): $label"; FAIL=1; fi
}
bash_() { jq -n --arg c "$1" '{command: $c}'; }
pre() { ev "$1" "$2" PreToolUse Bash "$(bash_ "$3")"; }
post() { ev 0 "post $1" PostToolUse Bash "$(bash_ "$1")" "$2"; }
read_() { ev 0 "read $1" PreToolUse Read "$(jq -n --arg f "$1" '{file_path: $f}')"; }

# Renders
SID=r1
pre 0 'span render passes' 'npx -y hyperframes@0.9.86 render --start 22 --end 40 -o a.mp4'
pre 2 'full render blocks' 'npx -y hyperframes@0.9.86 render -o full.mp4'
pre 2 'mid-line final does not count' 'npx hyperframes render -o full.mp4 # final'
pre 0 'final on its own line passes' 'npx hyperframes render -o full.mp4
# final'
pre 2 'second final within 20 min blocks' 'npx hyperframes render -o full2.mp4
# final'
T=$((T + 1300))
pre 0 'final after 20 min passes' 'npx hyperframes render -o full3.mp4
# final'
pre 0 'render --help passes' 'npx hyperframes render --help'
pre 0 'quoted render mention passes' "cd x && echo '{\"command\":\"npx hyperframes render -o x.mp4\"}' | jq ."
pre 0 'heredoc render mention passes' "cat > notes.md <<'EOF'
npx hyperframes render -o x.mp4
EOF"

# Installs
SID=i1
pre 0 'first install passes' 'cd app && ./gradlew :app:installDebug -q'
pre 2 'blind second install blocks' './gradlew installDebug -q'
read_ /x/shot.png
pre 2 'png Read is not a diagnosis' './gradlew installDebug -q'
read_ /x/app/src/main/res/values/themes.xml
pre 0 'install after a source Read passes' './gradlew installDebug -q'
pre 2 'short expect blocks' './gradlew installDebug -q
# expect: blue header'
pre 0 'valid expect passes' './gradlew installDebug -q
# expect: header turns #1E3A8A because colorPrimary now wins'
pre 2 'repeated expect text blocks' './gradlew installDebug -q
# expect: header turns #1E3A8A because colorPrimary now wins'
pre 0 'install after a screenshot test passes' './gradlew verifyRoborazziDebug && ./gradlew installDebug'
pre 0 'adb uninstall passes' 'adb uninstall com.example.app'
pre 0 'install named in a commit message passes' 'git commit -m "fix: installDebug flake"'
pre 2 'module-prefixed adb install blocks' 'adb -s emulator-5554 install app.apk'

# Slow steps
SID=w1
pre 0 'first slow run passes' 'cd /tmp/x && python patch1.py && uv run python -I build.py deck.pptx'
post 'cd /tmp/x && python patch1.py && uv run python -I build.py deck.pptx' 240000
pre 2 'blind rerun of the slow segment blocks' 'cd /tmp/x && python patch2.py && uv run python -I build.py deck.pptx'
ev 0 'grep' PreToolUse Grep '{"pattern":"wrap"}'
pre 0 'rerun after a Grep passes' 'cd /tmp/x && python patch3.py && uv run python -I build.py deck.pptx'
post 'cd /tmp/x && python patch3.py && uv run python -I build.py deck.pptx' 240000
pre 0 'rerun with an expect passes' 'uv run python -I build.py deck.pptx
# expect: slide 18 label box width now positive'
pre 0 'different unit passes' 'uv run python -I build.py deck.pptx --slides 18'
ev 0 'background rerun passes' PreToolUse Bash '{"command":"uv run python -I build.py deck.pptx","run_in_background":true}'
pre 0 'fast command passes' 'npx vitest run'
post 'npx vitest run' 2000
pre 0 'fast repeat passes' 'npx vitest run'
post 'uv run python -I build.py deck.pptx' 3000
pre 0 'segment cleared by a fast run passes' 'uv run python -I build.py deck.pptx'
pre 0 'unrelated command passes' 'ls -la'
SID=fresh pre 0 'session with no state passes' 'uv run python -I build.py deck.pptx'
SID=r1 CL_DISABLE=1 pre 0 'CL_DISABLE turns the gate off' 'npx hyperframes render -o off.mp4'

# Robustness
printf 'not json' | "$PY" "$DIR/costly_loop.py" 2>/dev/null || { echo "FAIL: bad input must fail open"; FAIL=1; }
grep -q '"rule": "install", "decision": "block"' "$CL_LOG" || { echo "FAIL: blocks are not logged"; FAIL=1; }

rm -rf "$TMP"
[ "$FAIL" -eq 0 ] && echo "costly_loop: all cases pass"
exit "$FAIL"
