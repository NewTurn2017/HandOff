#!/usr/bin/env python3
"""List handoff candidates for the current cwd's project. JSON to stdout."""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

STALE_WARN_HOURS = 24
STALE_BLOCK_HOURS = 24 * 7


def project_slug() -> str:
    if env := os.environ.get("HANDOFF_SLUG"):
        return env
    cwd = Path.cwd()
    try:
        top = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
        base = Path(top).name
    except Exception:
        base = cwd.name
    return re.sub(r"_+", "_", re.sub(r"[^A-Za-z0-9._-]", "_", base))


def parse_frontmatter(text: str) -> dict:
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    fm = {}
    for line in text[3:end].strip().splitlines():
        m = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip().strip('"\'')
    return fm


def main() -> int:
    root = Path(os.environ.get("HANDOFF_ROOT", str(Path.home() / ".claude" / "handoff")))
    slug = project_slug()
    project_dir = root / slug
    candidates = []
    if project_dir.is_dir():
        files = sorted(
            [p for p in project_dir.glob("handoff-*.md") if p.is_file()],
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        now = datetime.now(timezone.utc)
        for p in files:
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
            except Exception as e:
                continue
            fm = parse_frontmatter(text)
            mtime = datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc)
            age_hours = (now - mtime).total_seconds() / 3600
            candidates.append({
                "path": str(p),
                "saved_at": fm.get("savedAt") or mtime.isoformat(),
                "age_hours": round(age_hours, 2),
                "branch": fm.get("branch", ""),
                "next_prompt_short": fm.get("nextPromptShort", ""),
                "stale_warn": age_hours >= STALE_WARN_HOURS,
                "stale_block": age_hours >= STALE_BLOCK_HOURS,
            })

    print(json.dumps({
        "project_slug": slug,
        "handoff_dir": str(project_dir),
        "candidates": candidates,
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
