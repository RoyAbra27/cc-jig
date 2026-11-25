#!/usr/bin/env bash
# Run: bash ~/.claude/hooks/update.test.sh
# update.sh against a temp upstream and clone: a conflict aborts cleanly, a plain change applies.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
FAIL=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t UPDATE_SKIP_INSTALL=1
fail() { echo "FAIL: $1"; FAIL=1; }

U="$TMP/up"; C="$TMP/clone"
git init -q -b main "$U"
printf '{\n  "a": 1,\n  "b": 2,\n  "c": 3\n}\n' > "$U/settings.json"
cp "$DIR/../update.sh" "$DIR/../bootstrap.sh" "$U/"
git -C "$U" add -A && git -C "$U" commit -qm init
git clone -q "$U" "$C"

# 1. conflicting settings.json edits on both sides
sed -i.bak 's/"b": 2/"b": 20/' "$U/settings.json" && rm "$U/settings.json.bak"
git -C "$U" commit -qam "upstream b"
sed -i.bak 's/"b": 2/"b": 99/' "$C/settings.json" && rm "$C/settings.json.bak"
git -C "$C" commit -qam "local b"
(cd "$C" && bash update.sh >/dev/null 2>"$TMP/err"); rc=$?
[ "$rc" -eq 1 ] || fail "conflict: want exit 1, got $rc"
grep -q 'settings.json' "$TMP/err" || fail "conflict: error does not name settings.json"
jq empty "$C/settings.json" 2>/dev/null || fail "conflict: settings.json is not valid JSON"
[ -d "$C/.git/rebase-merge" ] || [ -d "$C/.git/rebase-apply" ] && fail "conflict: rebase left in progress"
grep -q '"b": 99' "$C/settings.json" || fail "conflict: local edit lost"

# 2. a non-conflicting upstream change applies; drop the conflicting local commit first
git -C "$C" reset -q --hard origin/main
sed -i.bak 's/"c": 3/"c": 30/' "$U/settings.json" && rm "$U/settings.json.bak"
git -C "$U" commit -qam "upstream c"
(cd "$C" && bash update.sh >/dev/null 2>"$TMP/err"); rc=$?
[ "$rc" -eq 0 ] || fail "clean update: want exit 0, got $rc: $(cat "$TMP/err")"
grep -q '"c": 30' "$C/settings.json" || fail "clean update: change not applied"
jq -e 'has("enabledPlugins") or has("attribution") | not' "$C/settings.json" >/dev/null || fail "clean update: no local/choices, yet settings.json gained keys"

# 3. an uncommitted settings.json edit that conflicts with upstream: stop, keep it in the stash, no markers
sed -i.bak 's/"b": 2/"b": 20/' "$U/settings.json" && rm "$U/settings.json.bak"
git -C "$U" commit -qam "upstream b again"
sed -i.bak 's/"b": 2/"b": 99/' "$C/settings.json" && rm "$C/settings.json.bak"
(cd "$C" && bash update.sh >/dev/null 2>"$TMP/err"); rc=$?
[ "$rc" -eq 1 ] || fail "autostash conflict: want exit 1, got $rc"
grep -q "conflict with the update.*git stash pop" "$TMP/err" || fail "autostash conflict: error does not point at the stash: $(cat "$TMP/err")"
git -C "$C" diff --quiet HEAD || fail "autostash conflict: tree is not the updated committed copy"
[ -n "$(git -C "$C" stash list)" ] || fail "autostash conflict: the edit is not in git stash list"
grep -q '<<<<<<<' "$C/settings.json" && fail "autostash conflict: conflict markers left in settings.json"
[ -z "$(git -C "$C" ls-files -u)" ] || fail "autostash conflict: unmerged index entries left"
git -C "$C" stash show -p 2>/dev/null | grep -q '"b": 99' || fail "autostash conflict: stash does not hold the local edit"
git -C "$C" stash clear; git -C "$C" checkout -q -- .

# 4. a non-tty skills run installs nothing unless asked
out=$(SKILLS_DIR="$TMP/skills" bash "$DIR/../scripts/install-skills.sh" --dry-run </dev/null 2>&1)
printf '%s' "$out" | grep -q 'would run' && fail "install-skills non-tty: would install skills nobody picked"

# 5. recorded bootstrap answers (local/choices) are replayed over what upstream ships
mkdir -p "$C/local" && printf 'MODS=ready\nSTYLE_CHECKS=drop\nSKIP=none\nEDITOR_CMD=none\n' > "$C/local/choices"
jq '.enabledPlugins = {"proof@local-mods": true, "ready@local-mods": true} | .attribution = {commit: ""}' "$U/settings.json" | tr -d '\r' > "$TMP/s" && mv "$TMP/s" "$U/settings.json"
git -C "$U" commit -qam "upstream enables mods, hides attribution"
(cd "$C" && bash update.sh >/dev/null 2>"$TMP/err"); rc=$?
[ "$rc" -eq 0 ] || fail "replay: want exit 0, got $rc: $(cat "$TMP/err")"
jq -e '.enabledPlugins["proof@local-mods"] == false and .enabledPlugins["ready@local-mods"] == true' "$C/settings.json" >/dev/null || fail "replay: upstream's mod default won over the recorded answer"
jq -e 'has("attribution") | not' "$C/settings.json" >/dev/null || fail "replay: style checks dropped, yet attribution is still set"
git -C "$C" diff --quiet HEAD -- settings.json || fail "replay: the choices were not committed in the clone"
# a non-tty bootstrap with no flags keeps the recorded answers too
(cd "$C" && bash bootstrap.sh --choices-only </dev/null >/dev/null 2>&1)
grep -qx 'MODS=ready' "$C/local/choices" || fail "replay: a non-tty run overwrote the recorded mods"
# a flag changes one answer and keeps the rest
(cd "$C" && bash bootstrap.sh --choices-only --mods all </dev/null >/dev/null 2>&1)
grep -qx 'MODS=all' "$C/local/choices" && grep -qx 'STYLE_CHECKS=drop' "$C/local/choices" || fail "replay: --mods did not change only the mods answer"
jq -e '.enabledPlugins["proof@local-mods"] == true' "$C/settings.json" >/dev/null || fail "replay: --mods all did not enable proof"

rm -rf "$TMP"
[ "$FAIL" -eq 0 ] && echo "update: all cases pass"
exit "$FAIL"
