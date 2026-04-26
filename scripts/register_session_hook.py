#!/usr/bin/env python3
"""Idempotently register the handoff-load SessionStart hook in ~/.claude/settings.json."""
import json
import os
import sys
from pathlib import Path

SETTINGS = Path(os.environ.get("CLAUDE_SETTINGS", str(Path.home() / ".claude" / "settings.json")))
HOOK_CMD = "$HOME/.claude/skills/handoff-load/scripts/load_hook.sh"


def main() -> int:
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    data = {}
    if SETTINGS.exists():
        try:
            data = json.loads(SETTINGS.read_text())
        except json.JSONDecodeError:
            print(f"refuse: {SETTINGS} is not valid JSON; leaving untouched", file=sys.stderr)
            return 1

    hooks = data.setdefault("hooks", {})
    session_start = hooks.setdefault("SessionStart", [])

    for matcher_block in session_start:
        for h in matcher_block.get("hooks", []):
            if h.get("type") == "command" and h.get("command") == HOOK_CMD:
                print(f"ok: hook already registered in {SETTINGS}")
                return 0

    session_start.append({
        "matcher": "*",
        "hooks": [{"type": "command", "command": HOOK_CMD}],
    })
    SETTINGS.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"added: SessionStart hook → {SETTINGS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
