#!/usr/bin/env bash
# HandOff installer — symlinks handoff-save / handoff-load into Claude Code and Codex skill dirs.
# Usage:
#   ./install.sh              # symlink into ~/.claude/skills and ~/.codex/skills (if present)
#   ./install.sh --claude     # only Claude Code
#   ./install.sh --codex      # only Codex
#   ./install.sh --uninstall  # remove the symlinks
#   ./install.sh --hook       # also register the SessionStart hook for handoff-load
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"

CLAUDE_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CODEX_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"

DO_CLAUDE=1
DO_CODEX=1
DO_HOOK=0
DO_UNINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --claude) DO_CODEX=0 ;;
    --codex) DO_CLAUDE=0 ;;
    --hook) DO_HOOK=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    -h|--help)
      sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

link_into() {
  local target_dir="$1"
  [ -d "$target_dir" ] || { echo "skip: $target_dir does not exist"; return 0; }
  for skill in handoff-save handoff-load; do
    local link="$target_dir/$skill"
    local src="$SKILLS_SRC/$skill"
    if [ -L "$link" ] || [ -e "$link" ]; then
      if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
        echo "ok:   $link → $src (already linked)"
        continue
      fi
      local backup="${link}.backup-$(date +%Y%m%d-%H%M%S)"
      echo "move: $link → $backup"
      mv "$link" "$backup"
    fi
    ln -s "$src" "$link"
    echo "link: $link → $src"
  done
}

unlink_from() {
  local target_dir="$1"
  for skill in handoff-save handoff-load; do
    local link="$target_dir/$skill"
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$SKILLS_SRC/$skill" ]; then
      rm "$link"
      echo "rm:   $link"
    fi
  done
}

if [ "$DO_UNINSTALL" -eq 1 ]; then
  [ "$DO_CLAUDE" -eq 1 ] && unlink_from "$CLAUDE_DIR"
  [ "$DO_CODEX" -eq 1 ]  && unlink_from "$CODEX_DIR"
  echo "uninstall complete."
  exit 0
fi

[ "$DO_CLAUDE" -eq 1 ] && link_into "$CLAUDE_DIR"
[ "$DO_CODEX" -eq 1 ]  && link_into "$CODEX_DIR"

if [ "$DO_HOOK" -eq 1 ]; then
  python3 "$REPO_ROOT/scripts/register_session_hook.py"
fi

echo
echo "done. verify with:"
echo "  ls -l \"$CLAUDE_DIR\"/handoff-* 2>/dev/null"
echo "  ls -l \"$CODEX_DIR\"/handoff-* 2>/dev/null"
