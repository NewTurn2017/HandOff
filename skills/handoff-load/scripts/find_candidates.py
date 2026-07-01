#!/usr/bin/env python3
"""List handoff candidates for the current cwd's project. JSON to stdout."""
from __future__ import annotations
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

STALE_WARN_HOURS = 24
STALE_BLOCK_HOURS = 24 * 7
CANONICAL_ROOT = Path.home() / ".handoff" / "sessions"
LEGACY_ROOT = Path.home() / ".claude" / "handoff"


def normalize_slug(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]", "_", value).strip("_")
    return slug or "project"


def project_slug() -> str:
    cwd = Path.cwd()
    if env := os.environ.get("HANDOFF_SLUG"):
        base = env
    else:
        try:
            top = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            base = Path(top).name
        except Exception:
            base = cwd.name
    return normalize_slug(base)


def handoff_roots() -> list[Path]:
    roots: list[Path] = []
    if env_root := os.environ.get("HANDOFF_ROOT"):
        roots.append(Path(env_root).expanduser())
    else:
        roots.append(CANONICAL_ROOT)

    if extra_roots := os.environ.get("HANDOFF_ROOTS"):
        for item in extra_roots.split(os.pathsep):
            if item:
                roots.append(Path(item).expanduser())

    if not os.environ.get("HANDOFF_ROOT"):
        roots.append(LEGACY_ROOT)

    deduped: list[Path] = []
    seen: set[str] = set()
    for root in roots:
        key = str(root)
        if key not in seen:
            deduped.append(root)
            seen.add(key)
    return deduped


def parse_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    fm: dict[str, str] = {}
    for line in text[3:end].strip().splitlines():
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if match:
            fm[match.group(1)] = match.group(2).strip().strip('"\'')
    return fm


def parse_saved_at(value: str):
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def main() -> int:
    slug = project_slug()
    roots = handoff_roots()
    records = []
    now = datetime.now(timezone.utc)

    for root in roots:
        project_dir = root / slug
        if not project_dir.is_dir():
            continue
        for path in project_dir.glob("handoff-*.md"):
            if not path.is_file():
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except Exception:
                continue
            fm = parse_frontmatter(text)
            mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
            saved_at_value = fm.get("savedAt", "")
            parsed_saved_at = parse_saved_at(saved_at_value)
            saved_at = parsed_saved_at or mtime
            age_hours = (now - saved_at).total_seconds() / 3600
            records.append(
                (
                    saved_at,
                    {
                        "path": str(path),
                        "root": str(root),
                        "saved_at": saved_at_value if parsed_saved_at else mtime.isoformat(),
                        "age_hours": round(age_hours, 2),
                        "branch": fm.get("branch", ""),
                        "runtime_agent": fm.get("runtimeAgent", fm.get("agent", "")),
                        "progress_percent": fm.get("progressPercent", ""),
                        "worktree_status": fm.get("worktreeStatus", ""),
                        "test_status": fm.get("testStatus", ""),
                        "next_prompt_short": fm.get("nextPromptShort", ""),
                        "stale_warn": age_hours >= STALE_WARN_HOURS,
                        "stale_block": age_hours >= STALE_BLOCK_HOURS,
                    },
                )
            )

    records.sort(key=lambda item: item[0], reverse=True)
    candidates = [candidate for _, candidate in records]

    primary_dir = roots[0] / slug if roots else CANONICAL_ROOT / slug
    print(
        json.dumps(
            {
                "project_slug": slug,
                "handoff_roots": [str(root) for root in roots],
                "handoff_dir": str(primary_dir),
                "candidates": candidates,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
