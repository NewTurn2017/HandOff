#!/usr/bin/env bash
# SessionStart hook: print a dry-run preview of the latest handoff for the current cwd.
# Designed to silent-fail — always exit 0, never block session start.

set +e

input=$(cat 2>/dev/null || echo '{}')
HANDOFF_HOOK_INPUT="$input" python3 <<'PYEOF' 2>/dev/null || true
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

STALE_BLOCK_HOURS = 24 * 7
CANONICAL_ROOT = Path.home() / ".handoff" / "sessions"
LEGACY_ROOT = Path.home() / ".claude" / "handoff"


def load_payload():
    raw = os.environ.get("HANDOFF_HOOK_INPUT") or "{}"
    try:
        return json.loads(raw)
    except Exception:
        return {}


def slug_for(cwd: Path) -> str:
    if env := os.environ.get("HANDOFF_SLUG"):
        return env
    try:
        top = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=str(cwd),
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        base = Path(top).name
    except Exception:
        base = cwd.name
    return re.sub(r"_+", "_", re.sub(r"[^A-Za-z0-9._-]", "_", base)).strip("_")


def roots():
    values = []
    if env_root := os.environ.get("HANDOFF_ROOT"):
        values.append(Path(env_root).expanduser())
    else:
        values.append(CANONICAL_ROOT)
    if extra := os.environ.get("HANDOFF_ROOTS"):
        values.extend(Path(item).expanduser() for item in extra.split(os.pathsep) if item)
    if not os.environ.get("HANDOFF_ROOT"):
        values.append(LEGACY_ROOT)

    out = []
    seen = set()
    for root in values:
        key = str(root)
        if key not in seen:
            out.append(root)
            seen.add(key)
    return out


def parse_frontmatter(text: str):
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fm = {}
    for line in text[3:end].strip().splitlines():
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if match:
            fm[match.group(1)] = match.group(2).strip().strip("'\"")
    return fm, text[end + 4 :]


def section(text: str, name: str) -> str:
    pat = re.compile(rf"##\s+{re.escape(name)}\s*\n(.*?)(?=\n##\s|\Z)", re.S)
    match = pat.search(text)
    return match.group(1).strip() if match else ""


def first_lines(value: str, limit: int):
    return [line for line in value.splitlines() if line.strip()][:limit]


def main() -> int:
    payload = load_payload()
    cwd_value = payload.get("cwd") or payload.get("workspace", {}).get("current_dir") or os.getcwd()
    cwd = Path(cwd_value).expanduser()
    if not cwd.exists():
        cwd = Path.cwd()

    slug = slug_for(cwd)
    latest = None
    for root in roots():
        project_dir = root / slug
        if not project_dir.is_dir():
            continue
        for path in project_dir.glob("handoff-*.md"):
            if path.is_file() and (latest is None or path.stat().st_mtime > latest.stat().st_mtime):
                latest = path

    if latest is None:
        return 0

    mtime = datetime.fromtimestamp(latest.stat().st_mtime, tz=timezone.utc)
    now = datetime.now(timezone.utc)
    age_h = int((now - mtime).total_seconds() // 3600)
    if age_h > STALE_BLOCK_HOURS:
        return 0

    try:
        raw = latest.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return 0

    fm, body = parse_frontmatter(raw)
    progress = section(body, "진행 상황") or section(body, "지금까지 한 일")
    priorities = section(body, "우선순위 목록") or section(body, "다음 단계")
    notes = section(body, "특이 사항")
    history = section(body, "작업 환경 및 이력")
    next_prompt = section(body, "이어갈 프롬프트 (복붙용)") or section(body, "이어갈 프롬프트")

    age_label = f"{age_h}시간 전" if age_h < 24 else f"{age_h // 24}일 전"
    warn = " ⚠️ 24시간 이상 경과" if age_h >= 24 else ""
    runtime_agent = fm.get("runtimeAgent") or fm.get("agent") or "unknown"
    branch = fm.get("branch", "?")
    progress_percent = fm.get("progressPercent", "unknown")
    worktree = fm.get("worktreeStatus", "unknown")
    tests = fm.get("testStatus", "unknown")

    lines = []
    lines.append(f"📂 이전 세션 핸드오프 발견: [{fm.get('project','?')}] {branch} · {age_label} 저장 · {runtime_agent}{warn}")
    lines.append(f"진행률: {progress_percent}% · 워크트리: {worktree} · 테스트: {tests}")
    lines.append(f"경로: {fm.get('cwd', str(cwd))}")
    lines.append(f"파일: {latest}")

    if progress:
        lines.append("\n진행 상황:")
        lines.extend(first_lines(progress, 6))
    if priorities:
        lines.append("\n우선순위:")
        lines.extend(first_lines(priorities, 6))
    if notes:
        lines.append("\n특이 사항:")
        lines.extend(first_lines(notes, 5))
    if history:
        lines.append("\n작업 환경 및 이력:")
        lines.extend(first_lines(history, 5))
    if next_prompt:
        lines.append("\n이어갈 프롬프트:")
        lines.append(next_prompt)

    lines.append("\n— 이어가시려면 그대로 진행하시고, 아니면 새 작업 지시를 입력하세요. (자동 실행하지 않습니다)")
    preview = "\n".join(lines)
    banner = lines[0] + "  ·  '이어가자' 또는 /handoff-load 로 복원"
    out = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": preview,
        },
        "systemMessage": banner,
    }
    print(json.dumps(out, ensure_ascii=False))
    return 0


sys.exit(main())
PYEOF

exit 0
