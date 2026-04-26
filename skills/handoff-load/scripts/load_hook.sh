#!/usr/bin/env bash
# SessionStart hook: print a dry-run preview of the latest handoff for the current cwd.
# Designed to silent-fail — always exit 0, never block session start.

set +e

# Read hook payload from stdin (JSON). Extract cwd if present, otherwise use $PWD.
input=$(cat 2>/dev/null || echo '{}')
cwd=$(printf "%s" "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin) if sys.stdin.isatty()==False else {}; print(d.get("cwd") or d.get("workspace",{}).get("current_dir") or "")' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
cd "$cwd" 2>/dev/null || true

ROOT="${HANDOFF_ROOT:-$HOME/.claude/handoff}"

# Compute project slug (mirror find_candidates.py logic)
if top=$(git rev-parse --show-toplevel 2>/dev/null); then
  base=$(basename "$top")
else
  base=$(basename "$cwd")
fi
slug=$(printf '%s' "$base" | tr -c '[:alnum:]._-' '_' | sed -E 's/_+/_/g; s/^_+|_+$//g')
slug="${HANDOFF_SLUG:-$slug}"

dir="$ROOT/$slug"
[ -d "$dir" ] || exit 0

# Find latest handoff-*.md by mtime
latest=$(ls -1t "$dir"/handoff-*.md 2>/dev/null | head -n 1)
[ -z "$latest" ] && exit 0
[ -f "$latest" ] || exit 0

# Compute age in hours
mtime=$(stat -f %m "$latest" 2>/dev/null || stat -c %Y "$latest" 2>/dev/null)
now=$(date +%s)
age_h=$(( (now - mtime) / 3600 ))

# Skip if older than 7 days (>168h)
[ "$age_h" -gt 168 ] && exit 0

# Build preview using python (simpler frontmatter parsing)
preview=$(python3 - "$latest" "$age_h" <<'PYEOF'
import sys, re
path, age_h = sys.argv[1], int(sys.argv[2])
try:
    text = open(path, encoding="utf-8", errors="replace").read()
except Exception:
    sys.exit(0)

fm = {}
if text.startswith("---"):
    end = text.find("\n---", 3)
    if end != -1:
        for line in text[3:end].strip().splitlines():
            m = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
            if m:
                fm[m.group(1)] = m.group(2).strip().strip("'\"")
        text = text[end+4:]

def section(name):
    pat = re.compile(rf"##\s+{re.escape(name)}\s*\n(.*?)(?=\n##\s|\Z)", re.S)
    m = pat.search(text)
    return m.group(1).strip() if m else ""

next_prompt = section("이어갈 프롬프트 (복붙용)") or section("이어갈 프롬프트")
next_steps = section("다음 단계")
done_so_far = section("지금까지 한 일")

age_label = f"{age_h}시간 전" if age_h < 24 else f"{age_h // 24}일 전"
warn = " ⚠️ 24시간 이상 경과" if age_h >= 24 else ""

out = []
out.append(f"📂 이전 세션 핸드오프 발견: [{fm.get('project','?')}] {fm.get('branch','?')} · {age_label} 저장{warn}")
out.append(f"파일: {path}")
if done_so_far:
    out.append("\n지금까지:")
    for line in done_so_far.splitlines()[:5]:
        out.append(line)
if next_steps:
    out.append("\n다음 단계:")
    for line in next_steps.splitlines()[:3]:
        out.append(line)
if next_prompt:
    out.append("\n이어갈 프롬프트:")
    out.append(next_prompt)
out.append("\n— 이어가시려면 그대로 진행하시고, 아니면 새 작업 지시를 입력하세요. (자동 실행하지 않습니다)")
print("\n".join(out))
PYEOF
)

# Emit JSON so Claude Code shows a user-visible banner (systemMessage)
# AND injects the full preview as additional context for the model.
# Falls back to plain stdout if python is missing.
if [ -n "$preview" ]; then
  python3 - "$preview" <<'PYEOF' 2>/dev/null || printf '%s\n' "$preview"
import json, sys
preview = sys.argv[1]
banner = next((ln for ln in preview.splitlines() if ln.startswith("📂")),
              "📂 이전 세션 핸드오프 발견")
banner += "  ·  '이어가자' 또는 /handoff-load 로 복원"
out = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": preview,
    },
    "systemMessage": banner,
}
print(json.dumps(out, ensure_ascii=False))
PYEOF
fi

exit 0
