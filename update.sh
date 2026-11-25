#!/usr/bin/env bash
# Update this config from its public repo: bash ~/.claude/update.sh
# Rebases your local commits onto upstream/main (origin/main when there is no upstream remote),
# keeping uncommitted work. A conflict aborts the rebase and leaves everything as it was.
# UPDATE_SKIP_INSTALL=1 stops after the rebase and settings.json check (used by hooks/update.test.sh).
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

git remote get-url upstream >/dev/null 2>&1 && REMOTE=upstream || REMOTE=origin
echo "== fetch $REMOTE"
git fetch "$REMOTE" || { echo "fetch failed; check your network and the $REMOTE remote." >&2; exit 1; }

GITDIR=$(git rev-parse --git-dir)
if [ -d "$GITDIR/rebase-merge" ] || [ -d "$GITDIR/rebase-apply" ]; then
  echo "A rebase is already in progress. Finish it (git rebase --continue) or cancel it (git rebase --abort), then rerun." >&2
  exit 1
fi

BEFORE=$(git rev-parse HEAD)
echo "== rebase onto $REMOTE/main"
if ! git rebase --autostash "$REMOTE/main"; then
  echo "Conflicting files:" >&2
  git diff --name-only --diff-filter=U | sed 's/^/  /' >&2
  git rebase --abort
  echo "Rebase aborted, nothing changed. To resolve: run 'git rebase $REMOTE/main' yourself, fix the files above, 'git add' them and 'git rebase --continue'." >&2
  exit 1
fi

if ! jq empty settings.json 2>/dev/null; then
  git checkout "$BEFORE" -- settings.json
  echo "settings.json was not valid JSON after the update, so your previous copy is restored. Fix the merge by hand before updating again." >&2
  exit 1
fi

[ "${UPDATE_SKIP_INSTALL:-}" = 1 ] && { echo "update: rebased, settings.json valid"; exit 0; }

if ! git diff --quiet "$BEFORE" HEAD -- bootstrap.sh scripts/install-skills.sh; then
  echo "== bootstrap.sh or install-skills.sh changed"
  bash bootstrap.sh || echo "warning: bootstrap.sh reported problems" >&2
fi
echo "== plugin marketplaces"
claude plugin marketplace update || echo "warning: marketplace update failed (continuing)" >&2
echo "== third-party skills"
bash scripts/install-skills.sh --update
echo "== smoke test"
bash hooks/smoke.test.sh
