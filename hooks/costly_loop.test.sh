#!/usr/bin/env bash
# Run: bash ~/.claude/hooks/costly_loop.test.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=$(command -v python || command -v python3)
TMP=$(mktemp -d)
REPO="$TMP/repo"; mkdir -p "$REPO/.git" "$REPO/sub"
export CL_STATE="$TMP/state" CL_LOG="$TMP/log.jsonl" CL_DURATIONS="$TMP/dur" CL_SLOW_MS=60000
export CL_BG_MS=999999999 CLAUDE_CODE_ENTRYPOINT=cli  # bounce off until its own section
unset CL_DISABLE
FAIL=0
T=1000

# ev <want-exit> <label> <event> <tool> <tool_input-json> [duration_ms]; env SID, AGENT, CWD
ev() {
  local want="$1" label="$2" event="$3" tool="$4" inp="$5" dur="${6:-0}" got
  T=$((T + 10))
  jq -n --arg e "$event" --arg t "$tool" --argjson i "$inp" --argjson d "$dur" --arg s "${SID:-s1}" \
    --arg a "${AGENT:-}" --arg c "${CWD:-$REPO}" \
    '{hook_event_name: $e, session_id: $s, tool_name: $t, tool_input: $i, duration_ms: $d, tool_use_id: "x", cwd: $c}
     + (if $a != "" then {agent_id: $a} else {} end)' 2>/dev/null \
    | CL_NOW=$T "$PY" "$DIR/costly_loop.py" 2>"$TMP/err"
  got=$?
  if [ "$got" -ne "$want" ]; then echo "FAIL (want $want, got $got): $label"; FAIL=1; fi
}
bash_() { jq -n --arg c "$1" '{command: $c}'; }
pre() { ev "$1" "$2" PreToolUse Bash "$(bash_ "$3")"; }
pre_bg() { ev "$1" "$2" PreToolUse Bash "$(jq -n --arg c "$3" '{command: $c, run_in_background: true}')"; }
post() { ev 0 "post $1" PostToolUse Bash "$(bash_ "$1")" "$2"; }
run() { pre 0 "$1" "$2"; post "$2" "$3"; }  # a call that passes and runs
read_() { ev 0 "read $1" PreToolUse Read "$(jq -n --arg f "$1" '{file_path: $f}')"; }
key() { "$PY" -c "import sys; sys.path.insert(0, sys.argv[1]); from costly_loop import step_key; print(step_key(sys.argv[2]))" "$DIR" "$1"; }
key_is() { local got; got=$(key "$1"); [ "$got" = "$2" ] || { echo "FAIL key: '$1' -> '$got', want '$2'"; FAIL=1; }; }

# Step keys
key_is 'python build.py --slide 3' 'python build.py --slide'
key_is 'uv run pytest -q tests/x' 'uv run pytest -q'
key_is 'RTK=1 rtk uv run pytest -q tests/y' 'uv run pytest -q'
key_is './gradlew :app:installDebug -q' 'gradlew :app:installDebug -q'
key_is 'npx -y hyperframes@0.9.86 render -o renders/v2.mp4' 'npx -y hyperframes render -o'
[ "$(key 'npx -y hyperframes@0.9.86 render -o renders/v1.mp4')" = "$(key 'npx -y hyperframes@0.9.86 render -o renders/v2.mp4')" ] \
  || { echo "FAIL key: v1/v2 output paths differ"; FAIL=1; }
key_is 'adb -s emulator-5554 shell input tap 1 2' 'adb -s shell input'
key_is 'docker compose -f x.yml up -d' 'docker compose -f up -d'
key_is 'F=$(ls -t *.jsonl' 'None'

# Renders
SID=r1
pre 0 'span render passes' 'npx -y hyperframes@0.9.86 render --start 22 --end 40 -o a.mp4'
pre 2 'full render blocks' 'npx -y hyperframes@0.9.86 render -o full.mp4'
pre 2 'mid-line final does not count' 'npx hyperframes render -o full.mp4 # final'
run 'final on its own line passes' 'npx hyperframes render -o full.mp4
# final' 90000
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

# Installs: the first blind reinstall is free, the second in a row blocks
SID=i1
pre 0 'install another hook then blocks (never runs)' './gradlew installDebug -q'
run 'first install that runs passes' 'cd app && ./gradlew :app:installDebug -q' 20000
run 'first blind reinstall is free' './gradlew installDebug -q' 20000
pre 2 'second blind reinstall blocks' './gradlew installDebug -q'
read_ /x/shot.png
pre 2 'png Read is not a diagnosis' './gradlew installDebug -q'
pre 2 'short expect blocks' './gradlew installDebug -q
# expect: blue header'
run 'valid expect passes' './gradlew installDebug -q
# expect: header turns #1E3A8A because colorPrimary now wins' 20000
pre 2 'second expect in the same streak blocks' './gradlew installDebug -q
# expect: padding becomes 16dp since Header.Home stops overriding'
read_ /x/app/src/main/res/values/themes.xml
run 'install after a source Read passes' './gradlew installDebug -q' 20000
run 'free blind reinstall after the reset' './gradlew installDebug -q' 20000
pre 2 'module-prefixed adb install blocks' 'adb -s emulator-5554 install app.apk'
run 'install after a screenshot test passes' './gradlew verifyRoborazziDebug && ./gradlew installDebug' 20000
pre 0 'adb uninstall passes' 'adb uninstall com.example.app'
pre 0 'install named in a commit message passes' 'git commit -m "fix: installDebug flake"'

# Slow steps (exact segments)
SID=w1
B='uv run python -I build.py deck.pptx'
run 'first slow run passes' "cd /tmp/x && python patch1.py && $B" 240000
run 'first blind rerun is free' "cd /tmp/x && python patch2.py && $B" 240000
pre 2 'second blind rerun blocks' "cd /tmp/x && python patch3.py && $B"
pre_bg 2 'background blind rerun blocks too' "$B"
ev 0 'grep' PreToolUse Grep '{"pattern":"wrap"}'
run 'rerun after a Grep passes' "cd /tmp/x && python patch4.py && $B" 240000
run 'free blind rerun' "$B" 240000
run 'expect passes once per streak' "$B
# expect: slide 18 label box width is now positive" 240000
pre 2 'second expect in the same streak blocks' "$B
# expect: caption line moves down one pixel on slide 7"
grep -q 's each)' "$TMP/err" || { echo "FAIL: slow block names no duration: $(cat "$TMP/err")"; FAIL=1; }
pre 0 'different unit passes' "$B --slides 18"
pre 0 'fast command passes' 'npx vitest run'
post 'npx vitest run' 2000
pre 0 'fast repeat passes' 'npx vitest run'
post "$B" 3000
pre 0 'step cleared by a fast run passes' "$B"
run 'one slide' 'python build.py --slide 3' 4000
pre 0 'next slide passes' 'python build.py --slide 4'
pre 0 'unrelated command passes' 'ls -la'
SID=fresh pre 0 'session with no state passes' "$B"

# Bounce: steps whose last 2 runs both took 30s+
export CL_BG_MS=30000
SID=b1
run 'slow suite 1' 'npm run verify:core' 70000
run 'slow suite 2' 'npm run verify:core' 72000
ev 0 'grep (so the loop rule stays out of the bounce cases)' PreToolUse Grep '{"pattern":"x"}'
pre 2 'known-slow step in the foreground bounces' 'npm run verify:core'
pre 0 'the same step with # fg passes' 'npm run verify:core
# fg'
pre_bg 0 'the same step in the background passes' 'npm run verify:core'
AGENT=sub1 pre 0 'a subagent call passes' 'npm run verify:core'
CLAUDE_CODE_ENTRYPOINT=sdk-cli pre 0 'a -p run passes' 'npm run verify:core'
CWD="$REPO/sub" pre 2 'same repo from a subdirectory bounces' 'npm run verify:core'
CWD="$TMP" pre 0 'another directory passes' 'npm run verify:core'
run 'pytest a' 'uv run pytest -q tests/a' 65000
run 'pytest b' 'uv run pytest -q tests/b' 66000
ev 0 'grep' PreToolUse Grep '{"pattern":"x"}'
pre 2 'a variant with another argument bounces' 'uv run pytest -q tests/c'
run 'build slow' 'npm run build' 70000
run 'build fast' 'npm run build' 5000
pre 0 'mixed history passes' 'npm run build'
run 'chained slow 1' 'make all && adb shell input tap 1 1' 90000
run 'chained slow 2' 'make all && adb shell input tap 1 1' 90000
pre 0 'a cheap step chained onto a slow one is not marked' 'adb shell input tap 5 5'
run 'poll 1' 'until [ -f done ]; do sleep 1; done' 70000
run 'poll 2' 'until [ -f done ]; do sleep 1; done' 70000
pre 0 'polling loops are never bounced' 'until [ -f done ]; do sleep 1; done'
LIST=$(CL_NOW=$T "$PY" "$DIR/costly_loop.py" --slow-list "$REPO")
printf '%s' "$LIST" | grep -q 'npm run verify:core' || { echo "FAIL: slow list misses verify:core: $LIST"; FAIL=1; }
printf '%s' "$LIST" | grep -q 'npm run build' && { echo "FAIL: slow list includes a mixed step"; FAIL=1; }
printf '%s' "$LIST" | grep -q 'verify:core` (~71s)' || { echo "FAIL: an example identical to its key is repeated: $LIST"; FAIL=1; }
printf '%s' "$LIST" | grep -q 'e.g. `uv run pytest -q tests/b`' || { echo "FAIL: a differing example is missing: $LIST"; FAIL=1; }
[ -z "$(CL_NOW=$T "$PY" "$DIR/costly_loop.py" --slow-list "$TMP/elsewhere")" ] || { echo "FAIL: list for a repo with no history"; FAIL=1; }
[ -z "$(CL_NOW=$((T + 31 * 86400)) "$PY" "$DIR/costly_loop.py" --slow-list "$REPO")" ] || { echo "FAIL: 30-day prune"; FAIL=1; }

# Learned slowness expires 14 days after the last foreground measurement; background runs do not renew it
R2="$TMP/repo2"; mkdir -p "$R2/.git"
post_bg() { ev 0 "post bg $1" PostToolUse Bash "$(jq -n --arg c "$1" '{command: $c, run_in_background: true}')"; }
SID=e1 CWD="$R2" run 'expiry slow 1' 'npm run e2e' 70000
SID=e1 CWD="$R2" run 'expiry slow 2' 'npm run e2e' 70000
SID=e1 CWD="$R2" ev 0 'grep' PreToolUse Grep '{"pattern":"x"}'
SID=e1 CWD="$R2" pre 2 'fresh slow step bounces' 'npm run e2e'
SID=e1 CWD="$R2" post_bg 'npm run e2e'
T=$((T + 15 * 86400))
SID=e1 CWD="$R2" pre 0 'slow step measured 15 days ago no longer bounces' 'npm run e2e'
SID=e2 CWD="$R2" run 'fresh slow 1' 'npm run lint:all' 70000
SID=e2 CWD="$R2" run 'fresh slow 2' 'npm run lint:all' 70000
LIST=$(CL_NOW=$T "$PY" "$DIR/costly_loop.py" --slow-list "$R2")
{ printf '%s' "$LIST" | grep -q 'lint:all' && ! printf '%s' "$LIST" | grep -q 'e2e'; } \
  || { echo "FAIL: slow list must show only the fresh step: $LIST"; FAIL=1; }

# Concurrent writers never leave a torn durations file, and the prune never deletes it mid-write
R3="$TMP/repo3"; mkdir -p "$R3/.git"
for round in 1 2 3 4 5; do
  for i in $(seq 1 20); do
    jq -n --arg c "npm run t$i" --arg r "$R3" \
      '{hook_event_name: "PostToolUse", session_id: "c", tool_name: "Bash", tool_input: {command: $c}, duration_ms: 1000, cwd: $r}' \
      | CL_NOW=$T CL_STATE="$TMP/state-c$i" "$PY" "$DIR/costly_loop.py" 2>/dev/null &
  done
  CL_NOW=$T "$PY" "$DIR/costly_loop.py" --slow-list "$R3" >/dev/null 2>&1 &
  wait
  n=$(ls "$CL_DURATIONS" | grep -c '\.json$')
  bad=$(for f in "$CL_DURATIONS"/*; do "$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null || echo "$f"; done)
  stray=$(ls "$CL_DURATIONS" | grep -v '\.json$')
  if [ "$n" -lt 2 ] || [ -n "$bad" ] || [ -n "$stray" ]; then
    echo "FAIL round $round: concurrent writes (json files $n, torn: $bad, stray: $stray)"; FAIL=1; break
  fi
done

# Robustness and logging
SID=r1 CL_DISABLE=1 pre 0 'CL_DISABLE turns the gate off' 'npx hyperframes render -o off.mp4'
printf 'not json' | "$PY" "$DIR/costly_loop.py" 2>/dev/null || { echo "FAIL: bad input must fail open"; FAIL=1; }
grep -q '"rule": "install", "decision": "block"' "$CL_LOG" || { echo "FAIL: blocks are not logged"; FAIL=1; }
grep -q '"decision": "pass:fg"' "$CL_LOG" || { echo "FAIL: # fg passes are not logged"; FAIL=1; }
grep -q '"decision": "bounce"' "$CL_LOG" || { echo "FAIL: bounces are not logged"; FAIL=1; }
grep -q '"v": 2' "$CL_LOG" || { echo "FAIL: log records lack the rule version"; FAIL=1; }
mkdir -p "$CL_STATE"; printf '[]' > "$CL_STATE/bad.json"
SID=bad pre 0 'malformed state fails open' 'npm test'
[ "$(grep -c '"error": "AttributeError"' "$TMP/loop-gate-errors.jsonl" 2>/dev/null)" = 1 ] \
  || { echo "FAIL: a swallowed error leaves no trace in loop-gate-errors.jsonl"; FAIL=1; }

rm -rf "$TMP"
[ "$FAIL" -eq 0 ] && echo "costly_loop: all cases pass"
exit "$FAIL"
