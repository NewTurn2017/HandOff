#!/usr/bin/env bash
# HandOff installer — symlinks handoff skills into supported coding-agent skill dirs.
# Usage:
#   ./install.sh              # symlink into every existing supported skill dir
#   ./install.sh --claude     # only Claude Code
#   ./install.sh --codex      # only Codex
#   ./install.sh --gajae      # only Gajae Code
#   ./install.sh --omx        # only OMX
#   ./install.sh --wcc        # only WCC / Whale Code
#   ./install.sh --uninstall  # remove the symlinks this repo created
#   ./install.sh --hook       # also register SessionStart hooks for selected dirs
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"

CLAUDE_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CODEX_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
GAJAE_DIR="${GAJAE_SKILLS_DIR:-$HOME/.gajae/skills}"
GJC_DIR="${GJC_SKILLS_DIR:-$HOME/.gjc/skills}"
OMX_DIR="${OMX_SKILLS_DIR:-$HOME/.omx/skills}"
WCC_DIR="${WCC_SKILLS_DIR:-$HOME/.wcc/skills}"

CLAUDE_SETTINGS_PATH="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
GAJAE_SETTINGS_PATH="${GAJAE_SETTINGS:-$HOME/.gajae/settings.json}"
GJC_SETTINGS_PATH="${GJC_SETTINGS:-$HOME/.gjc/settings.json}"
OMX_SETTINGS_PATH="${OMX_SETTINGS:-$HOME/.omx/settings.json}"
WCC_SETTINGS_PATH="${WCC_SETTINGS:-$HOME/.wcc/settings.json}"

DO_HOOK=0
DO_UNINSTALL=0
SELECTED="all"

select_target() {
  if [ "$SELECTED" = "all" ]; then
    SELECTED="$1"
  else
    SELECTED="$SELECTED $1"
  fi
}

for arg in "$@"; do
  case "$arg" in
    --claude) select_target "claude" ;;
    --codex) select_target "codex" ;;
    --gajae) select_target "gajae" ;;
    --gjc) select_target "gjc" ;;
    --omx) select_target "omx" ;;
    --wcc|--whale|--deepseek) select_target "wcc" ;;
    --hook) DO_HOOK=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    -h|--help)
      sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

enabled() {
  local name="$1"
  [ "$SELECTED" = "all" ] && return 0
  case " $SELECTED " in
    *" $name "*) return 0 ;;
    *) return 1 ;;
  esac
}

skill_links() {
  cat <<'EOF'
handoff-save|handoff-save
handoff-load|handoff-load
save_handoff_road|handoff-save
load_handoff_road|handoff-load
EOF
}

link_into() {
  local name="$1"
  local target_dir="$2"
  [ -d "$target_dir" ] || { echo "skip: $name ($target_dir does not exist)"; return 0; }

  while IFS='|' read -r link_name src_skill; do
    [ -n "$link_name" ] || continue
    local link="$target_dir/$link_name"
    local src="$SKILLS_SRC/$src_skill"
    if [ -L "$link" ] || [ -e "$link" ]; then
      if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
        echo "ok:   $name $link_name → $src (already linked)"
        continue
      fi
      local backup="${link}.backup-$(date +%Y%m%d-%H%M%S)"
      echo "move: $link → $backup"
      mv "$link" "$backup"
    fi
    ln -s "$src" "$link"
    echo "link: $name $link_name → $src"
  done <<EOF
$(skill_links)
EOF
}

unlink_from() {
  local name="$1"
  local target_dir="$2"
  while IFS='|' read -r link_name src_skill; do
    [ -n "$link_name" ] || continue
    local link="$target_dir/$link_name"
    local src="$SKILLS_SRC/$src_skill"
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
      rm "$link"
      echo "rm:   $name $link_name"
    fi
  done <<EOF
$(skill_links)
EOF
}

hook_cmd_for() {
  local target_dir="$1"
  if [ "${target_dir#$HOME/}" != "$target_dir" ]; then
    printf '$HOME/%s/handoff-load/scripts/load_hook.sh' "${target_dir#$HOME/}"
  else
    printf '%s/handoff-load/scripts/load_hook.sh' "$target_dir"
  fi
}

handle_target() {
  local name="$1"
  local dir="$2"
  local settings="$3"
  enabled "$name" || return 0

  if [ "$DO_UNINSTALL" -eq 1 ]; then
    unlink_from "$name" "$dir"
    return 0
  fi

  if [ ! -d "$dir" ]; then
    echo "skip: $name ($dir does not exist)"
    return 0
  fi

  link_into "$name" "$dir"
  if [ "$DO_HOOK" -eq 1 ] && [ -n "$settings" ]; then
    local hook_cmd
    hook_cmd="$(hook_cmd_for "$dir")"
    python3 "$REPO_ROOT/scripts/register_session_hook.py" "$settings" "$hook_cmd"
  fi
}

handle_target "claude" "$CLAUDE_DIR" "$CLAUDE_SETTINGS_PATH"
handle_target "codex" "$CODEX_DIR" ""
handle_target "gajae" "$GAJAE_DIR" "$GAJAE_SETTINGS_PATH"
handle_target "gjc" "$GJC_DIR" "$GJC_SETTINGS_PATH"
handle_target "omx" "$OMX_DIR" "$OMX_SETTINGS_PATH"
handle_target "wcc" "$WCC_DIR" "$WCC_SETTINGS_PATH"

if [ "$DO_UNINSTALL" -eq 1 ]; then
  echo "uninstall complete."
  exit 0
fi

echo
echo "done. canonical handoff storage: ${HANDOFF_ROOT:-$HOME/.handoff/sessions}"
echo "linked aliases: handoff-save, handoff-load, save_handoff_road, load_handoff_road"
echo "supported targets: claude codex gajae gjc omx wcc"
