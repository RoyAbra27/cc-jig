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
cp "$DIR/../update.sh" "$U/update.sh"
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

rm -rf "$TMP"
[ "$FAIL" -eq 0 ] && echo "update: all cases pass"
exit "$FAIL"
