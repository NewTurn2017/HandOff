#!/usr/bin/env bash
# Collect cwd + git metadata for handoff-save. Output: JSON to stdout, errors to stderr.
set -uo pipefail

cwd="$(pwd)"
git_top=""
branch=""
remote=""
head=""
status_summary=""
recent_commits=""

if git_top_try=$(git rev-parse --show-toplevel 2>/dev/null); then
  git_top="$git_top_try"
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  remote=$(git config --get remote.origin.url 2>/dev/null || echo "")
  head=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  modified=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  status_summary="${modified} changed files"
  recent_commits=$(git log -3 --pretty=format:'%h %s' 2>/dev/null | tr '\n' '|' | sed 's/|$//')
fi

if [ -n "$git_top" ]; then
  project_slug=$(basename "$git_top")
else
  project_slug=$(basename "$cwd")
fi

# Sanitize slug (strip newlines first to avoid trailing underscore)
project_slug=$(printf '%s' "$project_slug" | tr -c '[:alnum:]._-' '_' | sed -E 's/_+/_/g; s/^_+|_+$//g')

# Override
project_slug="${HANDOFF_SLUG:-$project_slug}"

esc() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

cat <<EOF
{
  "project_slug": $(esc "$project_slug"),
  "cwd": $(esc "$cwd"),
  "git_toplevel": $(esc "$git_top"),
  "branch": $(esc "$branch"),
  "remote": $(esc "$remote"),
  "head": $(esc "$head"),
  "status_summary": $(esc "$status_summary"),
  "recent_commits": $(esc "$recent_commits"),
  "saved_at": $(esc "$(date -Iseconds)")
}
EOF
