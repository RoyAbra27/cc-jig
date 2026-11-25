#!/usr/bin/env bash
# New-machine setup for this Claude Code config on macOS (Homebrew), Linux (apt-get or dnf) and Windows (winget, from Git Bash).
#   install Claude Code, then: git clone <this repo> ~/.claude && claude   (log in once, then quit)
# Safe to rerun: installed items are skipped. Updating an existing install is update.sh.
# Usage: bash ~/.claude/bootstrap.sh [--skills all|none|1,2,5] [--mods all|none|proof,shot]
#          [--style-checks keep|drop] [--skip none|mcp,statusline,lint,costly-loop] [--editor <cmd>|none]
#          [--dry-run] [--choices-only]
#        --skills        choose the third-party skills up front (default: asked interactively)
#        --mods          which mods to enable: proof, ready, shot, ratchet, compaction-insurance (default: all)
#        --style-checks  keep or drop the owner's style checks: guard.sh blocks em-dashes and Co-Authored-By,
#                        and settings.json hides the commit attribution trailer (default: keep)
#        --skip          components to leave out: mcp (the mobile MCP server), statusline (ccline),
#                        lint (lint-on-save hook), costly-loop (retry-loop hook) (default: none)
#        --editor        EDITOR for Claude Code sessions, none to unset it (default: the current value)
#        --dry-run       print the plan and change nothing
#        --choices-only  apply the recorded choices to settings.json and stop (update.sh uses this)
# A terminal run asks for each choice not given as a flag or recorded before. Answers are saved to the
# untracked local/choices and replayed on reruns, non-terminal runs and updates; a flag changes one.
set -uo pipefail
# The clone this script lives in (normally ${CLAUDE_CONFIG_DIR:-$HOME/.claude})
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS="" DRY=0 ONLY=0 F_MODS="" F_STYLE="" F_SKIP="" F_EDITOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skills) SKILLS="${2:?--skills needs all, none or a list like 1,2,5}"; shift 2 ;;
    --mods) F_MODS="${2:?--mods needs all, none or a list like proof,shot}"; shift 2 ;;
    --style-checks) F_STYLE="${2:?--style-checks needs keep or drop}"; shift 2 ;;
    --skip) F_SKIP="${2:?--skip needs none or a list like mcp,lint}"; shift 2 ;;
    --editor) F_EDITOR="${2:?--editor needs a command or none}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --choices-only) ONLY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$(uname -s)" in
  Darwin) OS=mac ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) OS=linux ;;
esac

step() { printf '\n== %s\n' "$1"; }
missing=()
# run <cmd...>: execute, or only print under --dry-run
run() { if [ "$DRY" = 1 ]; then echo "would run: $*"; else "$@"; fi; }

# Adopter choices (U-1): flag > recorded in local/choices > terminal prompt > the owner's setup
S="$REPO/settings.json" CHOICES="$REPO/local/choices"
MOD_NAMES="proof ready shot ratchet compaction-insurance" COMPONENTS="mcp statusline lint costly-loop"
MODS="" STYLE_CHECKS="" SKIP="" EDITOR_CMD=""
RECORDED=0
if [ -f "$CHOICES" ]; then . "$CHOICES"; RECORDED=1; fi
[ -n "$F_MODS" ] && MODS="$F_MODS"
[ -n "$F_STYLE" ] && STYLE_CHECKS="$F_STYLE"
[ -n "$F_SKIP" ] && SKIP="$F_SKIP"
[ -n "$F_EDITOR" ] && EDITOR_CMD="$F_EDITOR"
FLAGGED="$F_MODS$F_STYLE$F_SKIP$F_EDITOR"
# --choices-only with nothing recorded or flagged: the tracked settings.json already is the default
if [ "$ONLY" = 1 ] && [ "$RECORDED" = 0 ] && [ -z "$FLAGGED" ]; then exit 0; fi
# sed, not jq: a fresh machine gets jq only further down
EDITOR_DEF=$(sed -nE 's/^[[:space:]]*"EDITOR": "([^"]*)".*/\1/p' "$S" | head -1); EDITOR_DEF="${EDITOR_DEF:-none}"
if [ -t 0 ] && [ "$ONLY" = 0 ]; then
  ask() { local v; read -rp "$2 [$3]: " v; printf -v "$1" '%s' "${v:-$3}"; }
  [ -n "$MODS" ] || ask MODS "Enable which mods ($MOD_NAMES)? all / none / a comma list" all
  [ -n "$STYLE_CHECKS" ] || ask STYLE_CHECKS "Keep the owner's style checks (no em-dashes, no Co-Authored-By)? keep / drop" keep
  [ -n "$SKIP" ] || ask SKIP "Leave out any of: $COMPONENTS? none / a comma list" none
  [ -n "$EDITOR_CMD" ] || ask EDITOR_CMD "Editor command (none to unset)" "$EDITOR_DEF"
fi
MODS="${MODS:-all}" STYLE_CHECKS="${STYLE_CHECKS:-keep}" SKIP="${SKIP:-none}" EDITOR_CMD="${EDITOR_CMD:-$EDITOR_DEF}"
# in_list <value> <allowed names>: every comma-separated item is one of the names
in_list() { local x; for x in $(printf '%s' "$1" | tr ',' ' '); do case " $2 " in *" $x "*) ;; *) return 1 ;; esac; done; }
in_list "$MODS" "all none $MOD_NAMES" || { echo "--mods: expected all, none or a comma list of: $MOD_NAMES" >&2; exit 2; }
in_list "$SKIP" "none $COMPONENTS" || { echo "--skip: expected none or a comma list of: $COMPONENTS" >&2; exit 2; }
case "$STYLE_CHECKS" in keep|drop) ;; *) echo "--style-checks: expected keep or drop" >&2; exit 2 ;; esac
skipped() { case ",$SKIP," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# apply_choices: record the answers in local/choices and write them into settings.json
apply_choices() {
step "your choices"
echo "mods: $MODS / style checks: $STYLE_CHECKS / skip: $SKIP / editor: $EDITOR_CMD"
if ! command -v jq >/dev/null; then echo "would apply them to settings.json (needs jq)"; return 0; fi
CHOICES_TEXT=$(printf 'MODS=%q\nSTYLE_CHECKS=%q\nSKIP=%q\nEDITOR_CMD=%q\n' "$MODS" "$STYLE_CHECKS" "$SKIP" "$EDITOR_CMD")
if [ "$DRY" = 1 ]; then [ "$(cat "$CHOICES" 2>/dev/null)" = "$CHOICES_TEXT" ] || echo "would write: $CHOICES"
elif [ "$(cat "$CHOICES" 2>/dev/null)" != "$CHOICES_TEXT" ]; then
  mkdir -p "$REPO/local" && printf '%s\n' "$CHOICES_TEXT" > "$CHOICES" && echo "saved     $CHOICES"
fi
# Each choice maps to settings.json keys; the defaults reproduce the tracked file exactly.
# attribution.commit "" (empty) hides the commit trailer; guard.sh stays the backstop (STYLE_CHECKS=drop turns both off).
NEW_SETTINGS=$(jq --arg mods "$MODS" --arg style "$STYLE_CHECKS" --arg skip ",$SKIP," --arg editor "$EDITOR_CMD" --arg names "$MOD_NAMES" '
  ($names | split(" ")) as $all
  | (if $mods == "all" then $all elif $mods == "none" then [] else ($mods | split(",")) end) as $on
  | reduce $all[] as $m (.; .enabledPlugins["\($m)@local-mods"] = any($on[]; . == $m))
  | if $style == "keep" then .attribution = {commit: ""} else del(.attribution) end
  | if ($skip | contains(",statusline,")) then del(.statusLine, .subagentStatusLine) else . end
  | if ($skip | contains(",lint,")) then .hooks |= map_values(map(select(any(.hooks[]; .command | test("lint-on-save")) | not))) else . end
  | if ($skip | contains(",costly-loop,")) then .hooks |= map_values(map(select(any(.hooks[]; .command | test("costly_loop")) | not))) else . end
  | if $editor == "none" then del(.env.EDITOR) else .env.EDITOR = $editor end' "$S" | tr -d '\r') \
  || { echo "could not apply your choices to settings.json" >&2; return 1; }
if [ "$(jq -S . "$S")" = "$(printf '%s' "$NEW_SETTINGS" | jq -S .)" ]; then echo "ok        settings.json matches your choices"
elif [ "$DRY" = 1 ]; then echo "would update: settings.json from your choices"
else
  printf '%s\n' "$NEW_SETTINGS" > "$S" && echo "updated   settings.json from your choices"
  # A local commit is what update.sh rebases (README "Make it yours"). Never commit in a clone of the upstream repo itself.
  case "$(git -C "$REPO" remote get-url origin 2>/dev/null)" in
    *RoyAbra27/claude-config*) echo "Commit it so updates keep it: git -C \"$REPO\" commit -m 'chore: my bootstrap choices' settings.json" ;;
    *) if git -C "$REPO" commit -q -m "chore: my bootstrap choices" -- settings.json >/dev/null 2>&1; then echo "committed settings.json (your choices) in your clone"
       else echo "Commit it so updates keep it: git -C \"$REPO\" commit -m 'chore: my bootstrap choices' settings.json"; fi ;;
  esac
fi
}
if [ "$ONLY" = 1 ]; then apply_choices; exit $?; fi

# Origin is the public repo; a fork needs `upstream` so update.sh pulls from the original
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 && ! git -C "$REPO" remote get-url upstream >/dev/null 2>&1; then
  case "$(git -C "$REPO" remote get-url origin 2>/dev/null)" in
    *RoyAbra27/claude-config*) ;;
    *) step "upstream remote"; run git -C "$REPO" remote add upstream https://github.com/RoyAbra27/claude-config.git ;;
  esac
fi

SUDO=""
[ "$(id -u)" != 0 ] && command -v sudo >/dev/null && SUDO="sudo"

# Essentials only: git, jq, uv, node (npx, npm) and python 3 for hooks/costly_loop.py
step "essential packages (git jq uv node)"
install_pkgs() {
  case "$OS" in
    windows)
      for id in Git.Git jqlang.jq astral-sh.uv OpenJS.NodeJS.LTS; do
        if winget list --id "$id" -e --accept-source-agreements >/dev/null 2>&1; then echo "ok        $id"
        else run winget install --id "$id" -e --silent --accept-package-agreements --accept-source-agreements || missing+=("winget $id"); fi
      done ;;
    mac)
      command -v brew >/dev/null || { echo "Install Homebrew first (https://brew.sh), then rerun this script."; [ "$DRY" = 1 ] || exit 1; }
      for f in git jq uv node; do
        if brew list --formula "$f" >/dev/null 2>&1; then echo "ok        $f"
        else run brew install "$f" || missing+=("brew $f"); fi
      done ;;
    linux)
      if command -v apt-get >/dev/null; then
        { run $SUDO apt-get update && run $SUDO apt-get install -y git jq nodejs npm python3 curl; } || missing+=("apt-get packages")
      elif command -v dnf >/dev/null; then
        run $SUDO dnf install -y git jq nodejs npm python3 curl || missing+=("dnf packages")
      else
        echo "No apt-get or dnf found: install git, jq, node, npm, python3 and curl yourself."
      fi
      # uv is not in the distro repos
      if ! command -v uv >/dev/null; then
        if [ "$DRY" = 1 ]; then echo "would run: curl -LsSf https://astral.sh/uv/install.sh | sh"
        else curl -LsSf https://astral.sh/uv/install.sh | sh || missing+=("uv"); export PATH="$HOME/.local/bin:$PATH"; fi
      fi ;;
  esac
}
install_pkgs

if [ "$DRY" = 0 ]; then
  for bin in uv npx claude jq; do
    if ! command -v "$bin" >/dev/null; then
      echo "$bin is not on PATH yet (fresh installs often need a new terminal). Open a new terminal and rerun this script."
      exit 1
    fi
  done
  # costly_loop.py runs on python or python3; `--version` catches the Windows Store stub that command -v finds
  if ! python --version >/dev/null 2>&1 && ! python3 --version >/dev/null 2>&1; then
    echo "Python 3 not found: hooks/costly_loop.py stays off until it is installed."
    missing+=("python 3")
  fi
fi

apply_choices || missing+=("your choices: rerun bootstrap.sh")

step "uv tools"
# markitdown[all] needs an Azure pre-release dependency, so list the extras explicitly
run uv tool install "markitdown[pdf,docx,pptx,xlsx,xls,outlook,audio-transcription,youtube-transcription]" || missing+=("uv markitdown")

step "MCP servers (user scope, stored in ~/.claude.json)"
add_mcp() {
  local name="$1"; shift
  # a dry run starts no claude process, not even the read-only probe
  if [ "$DRY" = 1 ]; then echo "would run (unless already added): claude mcp add --scope user $name -- $*"
  elif claude mcp get "$name" >/dev/null 2>&1; then echo "ok        $name"
  else run claude mcp add --scope user "$name" -- "$@" || missing+=("mcp $name"); fi
}
if skipped mcp; then echo "skipped   mcp (your choice)"; else add_mcp mobile npx -y @mobilenext/mobile-mcp@1.0.16; fi

# Non-root Linux: the distro npm puts globals under /usr (EACCES), so send them to ~/.local
if [ "$OS" = linux ] && command -v npm >/dev/null && [ ! -w "$(npm prefix -g 2>/dev/null)" ]; then
  run npm config set prefix "$HOME/.local"; export PATH="$HOME/.local/bin:$PATH"
fi

step "agent-browser (headless browser CLI the skill router uses)"
# The browser download runs even when the CLI exists: a first run can fail after the npm step
if command -v agent-browser >/dev/null; then echo "ok        agent-browser"; run agent-browser install || missing+=("agent-browser install")
else run npm i -g agent-browser@0.42.0 && run agent-browser install || missing+=("agent-browser"); fi

# CCometixLine 2.0.1 (npm, published 2026-10-24): its postinstall copies the platform binary to ~/.claude/ccline/,
# where the settings.json statusLine command looks for it. It ignores CLAUDE_CONFIG_DIR, so this stays $HOME.
step "ccline status line"
if skipped statusline; then echo "skipped   ccline (your choice)"
elif { [ -x "$HOME/.claude/ccline/ccline" ] || [ -x "$HOME/.claude/ccline/ccline.exe" ]; }; then echo "ok        ccline"
else run npm i -g @cometix/ccline@2.0.1 || missing+=("ccline"); fi

step "third-party skills (upstream, see README Credits)"
bash "$REPO/scripts/install-skills.sh" ${SKILLS:+--select "$SKILLS"} $([ "$DRY" = 1 ] && echo --dry-run) || missing+=("third-party skills: rerun scripts/install-skills.sh")

step "self-check"
run uv run --script "$REPO/scripts/docread.py" --selftest || missing+=("docread selftest")

printf '\n== done\n'
if [ "$DRY" = 1 ]; then echo "Dry run: nothing was changed."
elif [ ${#missing[@]} -eq 0 ]; then
  echo "All steps succeeded. Start claude: plugins from settings.json download in the background; run /reload-plugins when prompted."
else
  echo "Needs attention:"; printf '  - %s\n' "${missing[@]}"; exit 1
fi
