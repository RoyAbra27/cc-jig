#!/usr/bin/env bash
# Run: bash ~/.claude/hooks/guard.test.sh
GUARD="${GUARD:-$(dirname "${BASH_SOURCE[0]}")/guard.sh}"
FAIL=0

check() {
  local want="$1" cmd="$2" got
  jq -n --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}' | env -u CLAUDE_JOB_DIR bash "$GUARD" 2>/dev/null
  got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL (want $want, got $got): $cmd"
    FAIL=1
  fi
}

check 2 'rm -rf build'
check 2 'cd x && rm -fr build'
check 0 'rm -rf $CLAUDE_JOB_DIR/tmp/l5 ${CLAUDE_JOB_DIR}/tmp/unz/'
check 2 'rm -rf $CLAUDE_JOB_DIR/tmp/..'
check 2 'rm -rf $CLAUDE_JOB_DIR/tmp/x build'
check 2 'rm -rf $CLAUDE_JOB_DIR/tmp/x && rm -rf build'
check 2 'git push --force origin main'
check 2 'git push -f'
check 2 'psql -c "DROP TABLE x"'
check 2 'git commit -m "feat: x

Co-Authored-By: Bot <b@x>"'

check 2 'git reset --hard HEAD~1'
check 2 'git clean -fd'
check 2 'cd x && git clean -xdf'
check 2 'git branch -D feature'
check 2 'git checkout .'
check 2 'git checkout -- .'
check 2 'git restore .'

check 0 "grep -nE 'pipefail|rm -rf|DROP' file"
check 0 'grep -n "git reset --hard" notes.md'
check 0 'git reset --soft HEAD~1'
check 0 'git clean -n'
check 0 'git branch -d merged'
check 0 'git checkout main'
check 0 'git checkout ./src/a.ts'
check 0 'git restore src/a.ts'
check 0 'echo "git push --force is blocked"'
check 0 'rm file.txt'
check 0 'git push origin main'

check 2 'head -c 1500 "users data/alice/token.txt"'
check 2 'cat ~/Downloads/users_data/notes.txt'
check 2 'cd x && cat .env'
check 2 'sed -n 1,5p rclone-token.txt'
check 2 'Get-Content C:\x\passwords.txt'
check 0 "grep -oE '^[A-Z_]+=' .env"
check 0 'wc -c "users data/alice/token.txt"'
check 2 'taskkill //F //IM node.exe //FI "WINDOWTITLE eq none"'
check 2 'taskkill /f /im python.exe'
check 2 'pkill node'
check 2 'Stop-Process -Name node -Force'
check 0 'taskkill //F //T //PID 1234'
check 0 'grep -n taskkill notes.md'
check 0 'cat .env.example'
check 0 'cat README.txt'
check 0 'head -5 out/nights.csv'
check 2 "cd x && python - <<'EOF'
print('a\\\\b')
EOF"
check 2 "uv run --with pillow python -I - <<'EOF'
import re; re.sub(r'\\s+', ' ', 'a  b')
EOF"
check 0 "python - <<'EOF'
print('no escapes here')
EOF"
check 0 "cat > notes.md <<'EOF'
a\\b
EOF"
check 0 'grep -n "python - <<" notes.md'
check 0 "python - <<'EOF'
print(1)
EOF
grep -E 'a\\.b' notes.md"
check 0 "cat > bin/node <<'EOF'
exec real-node \"\\\$@\" 2>\\&1
EOF"
check 2 "cat <<'EOF' | python -
import re; print(re.sub(r'\\bx', 'y', 'x'))
EOF"
check 2 "python.exe - <<'EOF'
import re; print(re.sub(r'\\bx', 'y', 'x'))
EOF"
check 0 "cat > notes.md <<'EOF'
run node on C:\\x
EOF"
check 2 "python - <<\\EOF
import re; print(re.sub(r'\\bx', 'y', 'x'))
EOF"

# Background sessions (CLAUDE_JOB_DIR set) never push or open PRs; interactive ones still can.
check_bg() {
  local want="$1" cmd="$2" got
  jq -n --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}' | CLAUDE_JOB_DIR=/tmp/job bash "$GUARD" 2>/dev/null
  got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL bg (want $want, got $got): $cmd"
    FAIL=1
  fi
}
check_bg 2 'gp'
check_bg 2 'git push origin x'
check_bg 2 'git -C repo push'
check_bg 2 'git -c x=y push'
check_bg 2 'git -c "a=b c" push'
check_bg 2 'cd x && gh pr create --fill'
check_bg 0 'echo "git push"'
check_bg 0 'grep -n "gp" x'
check_bg 0 'git status'
# The block message names the repo the push targeted (git -C), not the session's cwd.
msg=$(jq -n '{tool_name: "Bash", tool_input: {command: "git -C \"/some/repo\" push origin main"}}' | CLAUDE_JOB_DIR=/tmp/job bash "$GUARD" 2>&1)
printf '%s' "$msg" | grep -q 'git -C "/some/repo" push' || { echo "FAIL bg message names the wrong repo: $msg"; FAIL=1; }
check 0 'git push origin x'
check 0 'gh pr create --fill'

check 2 'adb uninstall com.example.app'
check 2 'adb -s emulator-5554 shell pm clear com.example.app'
check 0 'adb install -r app.apk'
check 0 'adb shell pm list packages'

check 2 "sed -i 's#under C:\\Users\\x#y#' f.sh"
check 2 "cd d && sed -i.bak 's/a\\(b\\)/\\1/' f"
check 0 "sed -i 's/a/b/' f"
check 0 "sed -n '1,5p' 'C:\\Users\\x.txt'"
check 2 "sed -E -i 's/\\bx/y/' f"
check 2 "/usr/bin/sed -i 's/a\\(b\\)/\\1/' f"

# rm -rf exceptions hold only for one plain line: no second line, no quoted target
for base in '$CLAUDE_JOB_DIR/tmp/x' '.superpowers/sdd/x'; do
  check 2 "rm -rf $base
rm -rf build"
  check_bg 2 "rm -rf $base
git push"
  check 2 "rm -rf $base \"\$HOME\""
  check 2 "rm -rf $base\"/../..\""
done
check 2 'rm -rf .superpowers/sdd/..'
check 0 'rm -rf .superpowers/sdd/plan-1'

# Force-push and recursive-delete spellings; --force-with-lease too (the user runs any force push)
check 2 'git push -uf origin main'
check 2 'git push origin +main'
check 2 'git push --force-with-lease'
check 2 'rm -r -f build'
check 2 'rm -f -r build'
check 2 'rm --recursive --force build'
check 0 'git push -u origin feat'
check 0 'git push --follow-tags origin main'
check 0 'rm -f file.txt'

# More background push and PR forms
check_bg 2 '(git push)'
check_bg 2 'git.exe push origin x'
check_bg 2 '/usr/bin/git push'
check_bg 2 'git --no-pager push'
check_bg 2 'git -c x=y -C repo push'
check_bg 2 'git subtree push --prefix d origin b'
check_bg 2 'gh pr new --fill'
check_bg 2 'gh api repos/o/r/pulls -f title=x'
check_bg 0 'git log --oneline -5'
check_bg 0 'gh pr view 12'

# Unreadable hook input fails closed
printf 'not json' | bash "$GUARD" 2>/dev/null; [ $? -eq 2 ] || { echo "FAIL malformed input passes"; FAIL=1; }

# A secret in the staged diff blocks the commit, and the message names the file, never the secret
SR=$(mktemp -d)
git -C "$SR" init -q
TOK="sk-ant-$(printf 'q%.0s' $(seq 1 30))"
printf 'key=%s\n' "$TOK" > "$SR/conf.txt"
git -C "$SR" add conf.txt 2>/dev/null
GA="$(cd "$(dirname "$GUARD")" && pwd)/$(basename "$GUARD")"
msg=$(cd "$SR" && jq -n '{tool_name: "Bash", tool_input: {command: "git commit -m x"}}' | env -u CLAUDE_JOB_DIR bash "$GA" 2>&1); rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL staged secret not blocked (got $rc)"; FAIL=1; }
printf '%s' "$msg" | grep -q 'conf.txt' || { echo "FAIL secret message does not name the file"; FAIL=1; }
printf '%s' "$msg" | grep -q 'qqqqqqqqqq' && { echo "FAIL secret message prints the secret"; FAIL=1; }
rm -rf "$SR"

# Style checks: em-dash and Co-Authored-By block by default; an adopter's STYLE_CHECKS=drop skips only those
ED=$(printf '\342\200\224')
edit() { jq -n --arg c "$2" '{tool_name: "Write", tool_input: {file_path: "/x/a.md", content: $c}}' | bash "$1" 2>/dev/null; echo $?; }
[ "$(edit "$GUARD" "a $ED b")" = 2 ] || { echo "FAIL em-dash not blocked"; FAIL=1; }
OPT=$(mktemp -d); mkdir -p "$OPT/hooks" "$OPT/local"
cp "$GUARD" "$OPT/hooks/guard.sh"; echo 'STYLE_CHECKS=drop' > "$OPT/local/choices"
[ "$(edit "$OPT/hooks/guard.sh" "a $ED b")" = 0 ] || { echo "FAIL STYLE_CHECKS=drop still blocks em-dashes"; FAIL=1; }
GUARD="$OPT/hooks/guard.sh" bash -c '
  t() { jq -n --arg c "$2" "{tool_name: \"Bash\", tool_input: {command: \$c}}" | env -u CLAUDE_JOB_DIR bash "$GUARD" 2>/dev/null; [ $? -eq "$1" ] || echo "FAIL STYLE_CHECKS=drop (want $1): $2"; }
  t 0 "git commit -m \"x

Co-Authored-By: Bot <b@x>\""
  t 2 "rm -rf build"
  t 2 "git push --force"' | grep . && FAIL=1
rm -rf "$OPT"

[ "$FAIL" -eq 0 ] && echo "guard: all cases pass"
exit "$FAIL"
