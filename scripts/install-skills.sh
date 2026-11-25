#!/usr/bin/env bash
# Install third-party skills from upstream (credited in README.md).
# Usage: bash install-skills.sh                 pick interactively
#        bash install-skills.sh --select all|none|1,2,5
#        add --dry-run to print the commands instead of running them
#        add --update to reinstall skills that are already installed
# Already-installed skills are skipped unless --update. Exits 1 if any selected install failed.
set -uo pipefail
SKILLS_DIR="${SKILLS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills}"
sk='npx -y skills@latest add'
T=(-g -a claude-code)

CATALOG=(
  "archify|diagrams and one-page explainers|$sk https://github.com/tt-a1i/archify --skill archify ${T[*]}"
  "impeccable|frontend design, critique and polish (+ 4 agents, design hook)|npx -y impeccable install --providers=claude --scope=global"
  "unslop|turn AI-looking UI into a designed interface|$sk heydamir/unslop --skill unslop ${T[*]}"
  "security-audit|Cloudflare's security review workflow|$sk cloudflare/security-audit-skill --skill security-audit ${T[*]}"
  "codebase-design|deep-module design vocabulary (mattpocock)|$sk mattpocock/skills --skill codebase-design ${T[*]}"
  "improve-codebase-architecture|find refactor opportunities (mattpocock)|$sk mattpocock/skills --skill improve-codebase-architecture ${T[*]}"
  "to-tickets|plan to dependency-ordered tickets (mattpocock)|$sk mattpocock/skills --skill to-tickets ${T[*]}"
  "wizard|guided bash scripts for manual steps (mattpocock)|$sk mattpocock/skills --skill wizard ${T[*]}"
  "android-material3-design-system|Material 3 theming for Android|$sk krutikJain/android-agent-skills --skill android-material3-design-system ${T[*]}"
  "android-viewsystem-foundations|XML layouts, Fragments, classic Android UI|$sk krutikJain/android-agent-skills --skill android-viewsystem-foundations ${T[*]}"
)

SELECT="" DRY=0 UPDATE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --update) UPDATE=1; shift ;;
    --select) SELECT="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ "$UPDATE" = 1 ] && SELECT="${SELECT:-all}"
if [ -z "$SELECT" ]; then
  i=1
  for row in "${CATALOG[@]}"; do
    IFS='|' read -r name desc _ <<<"$row"
    printf '%3d) %-32s %s\n' "$i" "$name" "$desc"; i=$((i+1))
  done
  if [ -t 0 ]; then read -rp "Install which skills? [all / none / e.g. 1,2,5] (all): " SELECT; fi
  SELECT="${SELECT:-all}"
fi

case "$SELECT" in
  all)  PICK=$(seq 1 ${#CATALOG[@]}) ;;
  none) echo "skipping third-party skills"; exit 0 ;;
  *)    PICK=$(printf '%s' "$SELECT" | tr ', ' '\n\n' | grep -v '^$') ;;
esac

failed=()
for n in $PICK; do
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt ${#CATALOG[@]} ]; then
    echo "invalid choice: $n (expected 1-${#CATALOG[@]})" >&2; failed+=("choice $n"); continue
  fi
  IFS='|' read -r name _ cmd <<<"${CATALOG[$((n-1))]}"
  # --update touches only what is installed; a fresh install is the job of plain runs
  if [ "$UPDATE" = 1 ] && [ ! -f "$SKILLS_DIR/$name/SKILL.md" ]; then continue; fi
  if [ "$UPDATE" = 0 ] && [ -f "$SKILLS_DIR/$name/SKILL.md" ]; then echo "ok        $name"; continue; fi
  if [ "$DRY" = 1 ]; then echo "would run $cmd"; continue; fi
  eval "$cmd" && echo "installed $name" || failed+=("skill $name")
done

# frontend-flow runs unslop itself; upstream lets it self-trigger and compete with Impeccable
HM="$SKILLS_DIR/unslop/SKILL.md"
if [ "$DRY" = 0 ] && [ -f "$HM" ] && ! grep -q '^disable-model-invocation:' "$HM"; then
  # awk, not sed -i: GNU and BSD (macOS) sed disagree on -i and on the 0,/re/ address
  awk '!d && /^name:/ {print "disable-model-invocation: true"; d=1} {print}' "$HM" > "$HM.tmp" && mv "$HM.tmp" "$HM" && echo "patched   unslop (user-invoke only)"
fi

[ ${#failed[@]} -eq 0 ] || { printf 'failed: %s\n' "${failed[@]}" >&2; exit 1; }
