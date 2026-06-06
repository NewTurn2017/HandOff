#!/usr/bin/env python3
"""Idempotently register the handoff-load SessionStart hook in a Claude-compatible settings file."""
from __future__ import annotations
import json
import os
import sys
from pathlib import Path

DEFAULT_SETTINGS = Path(os.environ.get("CLAUDE_SETTINGS", str(Path.home() / ".claude" / "settings.json")))
DEFAULT_HOOK_CMD = os.environ.get(
    "HANDOFF_HOOK_CMD",
    "$HOME/.claude/skills/handoff-load/scripts/load_hook.sh",
)


def main(argv: list[str]) -> int:
    settings = Path(argv[1]).expanduser() if len(argv) > 1 else DEFAULT_SETTINGS
    hook_cmd = argv[2] if len(argv) > 2 else DEFAULT_HOOK_CMD

    settings.parent.mkdir(parents=True, exist_ok=True)
    data = {}
    if settings.exists():
        try:
            data = json.loads(settings.read_text())
        except json.JSONDecodeError:
            print(f"refuse: {settings} is not valid JSON; leaving untouched", file=sys.stderr)
            return 1

    hooks = data.setdefault("hooks", {})
    session_start = hooks.setdefault("SessionStart", [])

    for matcher_block in session_start:
        for hook in matcher_block.get("hooks", []):
            if hook.get("type") == "command" and hook.get("command") == hook_cmd:
                print(f"ok: hook already registered in {settings}")
                return 0

    session_start.append(
        {
            "matcher": "*",
            "hooks": [{"type": "command", "command": hook_cmd}],
        }
    )
    settings.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"added: SessionStart hook → {settings}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
