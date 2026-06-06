#!/usr/bin/env bash
# Collect cwd + git + runtime metadata for handoff-save. Output: JSON to stdout, errors to stderr.
set -uo pipefail

cwd="$(pwd)"
handoff_root="${HANDOFF_ROOT:-$HOME/.handoff/sessions}"
legacy_handoff_root="$HOME/.claude/handoff"

git_top=""
branch=""
remote=""
head=""
status_summary="not a git repo"
status_short=""
worktree_status="not a git repo"
last_commit=""
recent_commits=""
changed_files="0"

if git_top_try=$(git rev-parse --show-toplevel 2>/dev/null); then
  git_top="$git_top_try"
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  remote=$(git config --get remote.origin.url 2>/dev/null || echo "")
  head=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  changed_files=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "${changed_files:-0}" = "0" ]; then
    status_summary="clean"
    worktree_status="clean"
  else
    status_summary="$changed_files changed files"
    worktree_status="dirty, $changed_files changed files"
  fi
  status_short=$(git status --short --branch 2>/dev/null || echo "")
  last_commit=$(git log -1 --pretty=format:'%h %ad %s' --date=iso-strict 2>/dev/null || echo "")
  recent_commits=$(git log -3 --pretty=format:'%h %ad %s' --date=short 2>/dev/null | tr '\n' '|' | sed 's/|$//' || echo "")
fi

if [ -n "$git_top" ]; then
  project_slug=$(basename "$git_top")
else
  project_slug=$(basename "$cwd")
fi

project_slug=$(printf '%s' "$project_slug" | tr -c '[:alnum:]._-' '_' | sed -E 's/_+/_/g; s/^_+|_+$//g')
project_slug="${HANDOFF_SLUG:-$project_slug}"

parent_process=$(ps -p "${PPID:-0}" -o comm= 2>/dev/null | tr -d '\n' || echo "")

runtime_agent_source="auto"
if [ -n "${HANDOFF_AGENT:-}" ]; then
  runtime_agent="$HANDOFF_AGENT"
  runtime_agent_source="HANDOFF_AGENT"
elif [ -n "${GAJAE_CODE:-}${GJCCODE:-}${GJC_HOME:-}${GJC_STATE_DIR:-}${GJC_SESSION_ID:-}${GJC_SESSION_CWD:-}${GJC_MODEL:-}" ] || printf '%s' "$parent_process" | grep -Eiq 'gajae|gjc'; then
  runtime_agent="gajae-code"
elif [ -n "${CODEX_HOME:-}${CODEX_CLI:-}" ] || printf '%s' "$parent_process" | grep -Eiq 'codex'; then
  runtime_agent="codex-cli"
elif [ -n "${OMX_HOME:-}${OMX_CODE:-}${OMX_ROOT:-}${OMXBOX_ACTIVE:-}${OMX_ENTRY_PATH:-}" ] || printf '%s' "$parent_process" | grep -Eiq 'omx'; then
  runtime_agent="omx"
elif [ -n "${WCC_HOME:-}${WHALE_CODE:-}" ] || printf '%s' "$parent_process" | grep -Eiq 'wcc|whale|deepseek'; then
  runtime_agent="wcc-whale-deepseek"
elif [ -n "${CLAUDECODE:-}${CLAUDE_CODE:-}${CLAUDE_PLUGIN_ROOT:-}" ] || printf '%s' "$parent_process" | grep -Eiq 'claude'; then
  runtime_agent="claude-code"
else
  runtime_agent="unknown"
  runtime_agent_source="unknown"
fi

case "$runtime_agent" in
  claude-code) agent_home="$HOME/.claude" ;;
  codex-cli) agent_home="$HOME/.codex" ;;
  gajae-code) agent_home="$HOME/.gjc/agent" ;;
  omx) agent_home="$HOME/.omx" ;;
  wcc-whale-deepseek) agent_home="$HOME/.wcc" ;;
  *) agent_home="" ;;
esac

test_status="${HANDOFF_TEST_STATUS:-not recorded}"

esc() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

cat <<EOF
{
  "project_slug": $(esc "$project_slug"),
  "handoff_root": $(esc "$handoff_root"),
  "legacy_handoff_root": $(esc "$legacy_handoff_root"),
  "cwd": $(esc "$cwd"),
  "git_toplevel": $(esc "$git_top"),
  "branch": $(esc "$branch"),
  "remote": $(esc "$remote"),
  "head": $(esc "$head"),
  "status_summary": $(esc "$status_summary"),
  "status_short": $(esc "$status_short"),
  "worktree_status": $(esc "$worktree_status"),
  "changed_files": $(esc "$changed_files"),
  "last_commit": $(esc "$last_commit"),
  "recent_commits": $(esc "$recent_commits"),
  "runtime_agent": $(esc "$runtime_agent"),
  "runtime_agent_source": $(esc "$runtime_agent_source"),
  "runtime_agent_home": $(esc "$agent_home"),
  "parent_process": $(esc "$parent_process"),
  "test_status": $(esc "$test_status"),
  "saved_at": $(esc "$(date -Iseconds)")
}
EOF
