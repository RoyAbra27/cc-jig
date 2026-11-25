#!/usr/bin/env bash
# New-machine setup for this Claude Code config on macOS (Homebrew), Linux (apt-get or dnf) and Windows (winget, from Git Bash).
#   install Claude Code, then: git clone <this repo> ~/.claude && claude   (log in once, then quit)
# Safe to rerun: installed items are skipped. Updating an existing install is update.sh.
# Usage: bash ~/.claude/bootstrap.sh [--skills all|none|1,2,5] [--dry-run]
#        --skills  choose the third-party skills up front (default: asked interactively)
#        --dry-run print the plan and change nothing
set -uo pipefail
REPO="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILLS="" DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --skills) SKILLS="${2:?--skills needs all, none or a list like 1,2,5}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
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
        run $SUDO apt-get install -y git jq nodejs npm python3 curl || missing+=("apt-get packages")
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

step "uv tools"
# markitdown[all] needs an Azure pre-release dependency, so list the extras explicitly
run uv tool install "markitdown[pdf,docx,pptx,xlsx,xls,outlook,audio-transcription,youtube-transcription]" || missing+=("uv markitdown")

step "MCP servers (user scope, stored in ~/.claude.json)"
add_mcp() {
  local name="$1"; shift
  if claude mcp get "$name" >/dev/null 2>&1; then echo "ok        $name"
  else run claude mcp add --scope user "$name" -- "$@" || missing+=("mcp $name"); fi
}
add_mcp mobile npx -y @mobilenext/mobile-mcp@1.0.16

step "agent-browser (headless browser CLI the skill router uses)"
if command -v agent-browser >/dev/null; then echo "ok        agent-browser"
else run npm i -g agent-browser@0.42.0 && run agent-browser install || missing+=("agent-browser"); fi

# CCometixLine 2.0.1 (npm, published 2026-10-24): its postinstall copies the platform binary to ~/.claude/ccline/,
# where the settings.json statusLine command looks for it
step "ccline status line"
if { [ -x "$HOME/.claude/ccline/ccline" ] || [ -x "$HOME/.claude/ccline/ccline.exe" ]; }; then echo "ok        ccline"
else run npm i -g @cometix/ccline@2.0.1 || missing+=("ccline"); fi

step "third-party skills (upstream, see README Credits)"
run bash "$REPO/scripts/install-skills.sh" ${SKILLS:+--select "$SKILLS"} || missing+=("third-party skills: rerun scripts/install-skills.sh")

step "self-check"
run uv run --script "$REPO/scripts/docread.py" --selftest || missing+=("docread selftest")

printf '\n== done\n'
if [ "$DRY" = 1 ]; then echo "Dry run: nothing was changed."
elif [ ${#missing[@]} -eq 0 ]; then
  echo "All steps succeeded. Start claude: plugins from settings.json download in the background; run /reload-plugins when prompted."
else
  echo "Needs attention:"; printf '  - %s\n' "${missing[@]}"; exit 1
fi
