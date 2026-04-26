---
name: handoff-load
description: This skill should be used when the user asks to "핸드오프 로드", "이전 세션 이어가기", "이어서 작업", "지난번 어디까지 했지", "핸드오프 불러와", "/handoff-load", "resume last session", "load handoff", "continue from last handoff". Also use when the user starts a new session and wants to pick up where they left off, or when they want to review/select among multiple handoff documents instead of relying on the SessionStart auto-load. Trigger even if the user only says "이어가자" while clearly intending to resume the previous handoff for the current project.
---

# Hand-off Load

> 현재 프로젝트(cwd 기준)의 최신 핸드오프 문서를 찾아 요약 + 이어갈 프롬프트를 제시한다. SessionStart hook이 자동 dry-run 미리보기를 보여주고, 이 스킬은 수동 재호출/후보 선택용이다.

## When this skill applies

- 사용자가 명시적으로 핸드오프를 불러오고 싶을 때
- SessionStart hook이 무언가 보여줬고, 사용자가 다른 후보를 보거나 다시 로드하고 싶을 때
- Hook이 가드레일에 막혀 자동 로드를 스킵했지만 사용자가 강제로 로드하고 싶을 때

자동 SessionStart 로드는 별도 스크립트(`scripts/load_hook.sh`)가 담당한다. 이 스킬은 사용자가 직접 호출했을 때 동작한다.

## Workflow

### Step 1: Locate candidate handoffs
**Type**: script

Run `scripts/find_candidates.py` to list handoffs for the current project:

```bash
python3 "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/skills/handoff-load/scripts/find_candidates.py"
```

It prints JSON: `{ "project_slug": ..., "handoff_dir": ..., "candidates": [{"path", "saved_at", "age_hours", "next_prompt_short"}] }`. Most-recent first.

### Step 2: Pick a handoff
**Type**: review

- 0 candidates → tell the user "이 프로젝트에 저장된 핸드오프가 없어요. 먼저 `/handoff-save`를 실행해주세요." and stop.
- 1 candidate → use it directly.
- 2+ candidates → present them via `AskUserQuestion`. Each option label = `{age} ago — {next_prompt_short}`. Always include a "취소" option.

If the chosen handoff is older than 7 days, ask the user to confirm before loading.

### Step 3: Read and summarize
**Type**: rag + prompt

1. Read the chosen file.
2. Verify cwd matches `git rev-parse --show-toplevel` (or current cwd if not a repo). If mismatch, warn.
3. Verify branch matches current branch. If mismatch, warn but proceed.
4. Summarize the handoff for the user in this format:

```
📂 [{project}] {branch} · {age} 전 저장
━━━━━━━━━━━━━━━━━━━━━━━━━━━
지금까지: {3-5줄 요약}
다음 단계: {1-3줄}

이어갈 프롬프트:
> {복붙용 프롬프트 그대로}

이대로 이어갈까요? 아니면 새로 시작할까요?
```

### Step 4: User confirms direction
**Type**: prompt

Wait for the user to either accept ("ㄱㄱ", "이어가자") and start working on the next prompt, or reject ("새로 할게") in which case the loaded context is dropped and you proceed with fresh intent.

Do NOT auto-execute the next prompt without user confirmation. The skill restores context, the user decides what happens next.

## Why these design choices

- **Candidate listing over guessing** — when 2+ handoffs exist for the same project (e.g., parallel branches, abandoned attempt), guessing the wrong one corrupts the session premise. Show, don't guess.
- **Branch mismatch warns, doesn't block** — the user may have intentionally checked out a different branch to continue work; blocking would be paternalistic.
- **Confirmation before action** — the skill restores the prompt; the user owns the decision to act on it.
- **Hook handles the auto path, skill handles the manual path** — separating these keeps each path simple and predictable.

## Settings

| Setting | Default | How to change |
|---------|---------|---------------|
| Storage root | `~/.claude/handoff/` | Set `HANDOFF_ROOT` env var |
| Stale threshold (warn) | 24 hours | Edit `STALE_WARN_HOURS` in `scripts/find_candidates.py` |
| Stale threshold (require confirm) | 7 days | Edit `STALE_BLOCK_HOURS` in `scripts/find_candidates.py` |

## Scripts

- **`scripts/find_candidates.py`** — Lists handoff candidates for the current project (cwd-based slug match).
- **`scripts/load_hook.sh`** — SessionStart hook entry point. Outputs a dry-run preview to stdout (which Claude Code injects into the new session as additional context). Designed to silent-fail (always exit 0).

## SessionStart hook setup

To enable automatic dry-run preview on new sessions, register `scripts/load_hook.sh` as a SessionStart hook in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/skills/handoff-load/scripts/load_hook.sh" }
        ]
      }
    ]
  }
}
```

The hook runs on every new session start, computes the project slug from cwd, and if a fresh (≤7 days) handoff exists, prints a 3-5 line preview + the "이어갈 프롬프트" so the new session can see it. The user then decides whether to act on it.
