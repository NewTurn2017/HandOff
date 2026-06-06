# Repository Guidelines

## Project Overview
HandOff is the single source of truth for two cross-agent coding skills: `handoff-save` checkpoints a session into a Markdown handoff, and `handoff-load` restores the latest relevant handoff. It supports Claude Code, Codex CLI, Gajae Code/GJC, OMX, and WCC/Whale Code/DeepSeek-style harnesses.

Handoff output is not stored in git. The canonical runtime location is `~/.handoff/sessions/{project_slug}/`; load-side scripts also read legacy `~/.claude/handoff/{project_slug}/` documents.

## Architecture & Data Flow
- **Save flow** (`skills/handoff-save/SKILL.md`): collect cwd/git/runtime metadata with `skills/handoff-save/scripts/collect_meta.sh`, synthesize progress/priority/special-notes/environment sections, auto-save without confirmation, redact with `skills/handoff-save/scripts/redact.py`, then write `handoff-YYYYMMDD-HHmmss.md` and `latest.md` under `HANDOFF_ROOT`.
- **Load flow** (`skills/handoff-load/SKILL.md`): list candidates with `skills/handoff-load/scripts/find_candidates.py`, search canonical/additional/legacy roots, show branch/runtime/progress/test status, warn on mismatches, and wait for user direction before executing the saved prompt.
- **SessionStart hook** (`skills/handoff-load/scripts/load_hook.sh`): reads hook JSON from stdin, computes the project slug from cwd, finds a fresh handoff (<=7 days), emits Claude-compatible hook JSON with a banner and additional context, and always exits `0`.
- **Installer flow** (`bootstrap.sh`, `bootstrap.ps1`, `install.sh`): clone/update into `HANDOFF_HOME` (default `~/.handoff`), link skill directories and aliases into existing agent skill dirs, and optionally register SessionStart hooks.

## Key Directories
- `skills/handoff-save/` — save skill prompt and save-side scripts.
- `skills/handoff-load/` — load skill prompt, candidate finder, and SessionStart hook.
- `skills/*/scripts/` — dependency-light runtime helpers invoked by skills.
- `scripts/` — repository-level helpers, currently hook registration.
- Project root — installers, README, license, and AI guidance.

## Development Commands
There is no build step or package manager install.

```bash
./install.sh                # link all supported existing agent dirs
./install.sh --hook         # link and register supported SessionStart hooks
./install.sh --claude       # limit target
./install.sh --gajae
./install.sh --omx
./install.sh --wcc
./install.sh --uninstall

bash skills/handoff-save/scripts/collect_meta.sh
printf 'TEST_API_KEY=sk-abcdefghijklmnopqrstuvwx\n' | python3 skills/handoff-save/scripts/redact.py
python3 skills/handoff-load/scripts/find_candidates.py
echo '{}' | bash skills/handoff-load/scripts/load_hook.sh
```

Bootstrap examples:
```bash
curl -fsSL https://raw.githubusercontent.com/NewTurn2017/HandOff/main/bootstrap.sh | bash
curl -fsSL https://raw.githubusercontent.com/NewTurn2017/HandOff/main/bootstrap.sh | bash -s -- --hook
```

## Code Conventions & Common Patterns
- Prefer shell and Python standard library only. Do not add Node/Bun/npm or external Python dependencies without adding real packaging.
- Installer scripts use strict shell behavior; hook scripts must silent-fail and never block session startup.
- Python scripts expose `main() -> int`, use `Path`, emit JSON with `ensure_ascii=False`, and return through `sys.exit(main(...))`.
- Runtime scripts communicate through stdout: metadata/candidates as JSON, redaction as stdin-to-stdout text, hooks as Claude-compatible JSON.
- Keep operations idempotent. Existing real files/dirs are moved to `*.backup-YYYYMMDD-HHmmss`; existing matching symlinks are left alone.
- Public env overrides include `HANDOFF_ROOT`, `HANDOFF_ROOTS`, `HANDOFF_SLUG`, `HANDOFF_AGENT`, `HANDOFF_TEST_STATUS`, `HANDOFF_HOME`, `*_SKILLS_DIR`, and `*_SETTINGS`.
- Redact before writing handoffs. Extend `redact.py` when capturing new secret families.
- Save is automatic by default; load restores context but does not execute the continuation prompt without user direction.

## Important Files
- `README.md` — canonical user-facing install, workflow, schema, environment, and smoke-test docs.
- `install.sh` — multi-agent installer/uninstaller and hook registrar.
- `bootstrap.sh` / `bootstrap.ps1` — macOS/Linux and Windows bootstrap installers.
- `scripts/register_session_hook.py` — idempotently updates Claude-compatible settings files with SessionStart hooks.
- `skills/handoff-save/SKILL.md` — enhanced save workflow, schema, no-confirm behavior, auto-compact design.
- `skills/handoff-load/SKILL.md` — load workflow, unified root search, agent mismatch handling.
- `skills/handoff-save/scripts/collect_meta.sh` — cwd/git/worktree/runtime metadata JSON generator.
- `skills/handoff-save/scripts/redact.py` — secret masker.
- `skills/handoff-load/scripts/find_candidates.py` — canonical/additional/legacy candidate discovery.
- `skills/handoff-load/scripts/load_hook.sh` — silent SessionStart preview hook.

## Runtime/Tooling Preferences
- Required local tools: `git`, `bash`, and `python3` on macOS/Linux; `git` and `python` on Windows.
- Windows symlinks require Developer Mode or admin PowerShell; otherwise `bootstrap.ps1` copies skills.
- Windows hooks still run `load_hook.sh`, so Git Bash or WSL must be on PATH for hook execution.
- Supported default skill dirs: `~/.claude/skills`, `~/.codex/skills`, `~/.gajae/skills`, `~/.gjc/skills`, `~/.omx/skills`, `~/.wcc/skills`.
- `.gitignore` intentionally ignores `.DS_Store`, `*.backup-*`, `__pycache__/`, and `*.pyc`.

## Testing & QA
No automated test framework, CI config, coverage config, or lint config is present. Verify changes with targeted smoke tests.

Recommended QA:
- Metadata changes: run `bash skills/handoff-save/scripts/collect_meta.sh` in a git repo and inspect JSON.
- Redaction changes: pipe representative secrets through `python3 skills/handoff-save/scripts/redact.py`.
- Candidate discovery: create temporary handoffs under `HANDOFF_ROOT`/`HANDOFF_SLUG` and run `python3 skills/handoff-load/scripts/find_candidates.py`.
- Hook changes: run `echo '{"cwd":"/path/to/project"}' | HANDOFF_ROOT=/tmp/... bash skills/handoff-load/scripts/load_hook.sh`; verify hit and miss cases exit `0`.
- Installer changes: test with temporary `CLAUDE_SKILLS_DIR`, `GAJAE_SKILLS_DIR`, `WCC_SKILLS_DIR`, and settings paths before touching real user dirs.
