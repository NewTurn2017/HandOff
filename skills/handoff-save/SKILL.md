---
name: handoff-save
description: This skill should be used when the user asks to "핸드오프 저장", "핸드오프 만들어줘", "여기까지 저장해줘", "세션 마무리", "다음 세션에 이어갈 수 있게 저장", "박제해줘", "wrap up session", "save handoff", "checkpoint this session". Use this skill whenever the user wants to capture the current session state (current project, working folder, plan progress, what was implemented, and the next prompt to continue with) into a markdown handoff document so a future session can resume without losing context. Trigger even if the user only says "핸드오프" while clearly intending to save, not load.
---

# Hand-off Save

> 현재 세션의 작업 상태와 "다음에 이어갈 프롬프트"를 마크다운 핸드오프 문서로 저장한다. 새 세션에서 `handoff-load`가 이 문서를 자동으로 불러온다.

## When this skill applies

Trigger when the user wants to checkpoint the current session — typically before context window fills up, end of day, model/session switch, or any "save what we've done so far + the next step" intent. The optional argument is a free-form note (e.g., `/handoff-save 내일은 결제 모듈부터`) that becomes the `nextPromptShort` hint.

## Workflow

### Step 1: Collect session metadata
**Type**: script

Run `scripts/collect_meta.sh` from the current working directory. It returns JSON with `project_slug`, `cwd`, `git_toplevel`, `branch`, `remote`, `head`, `status_summary`, `recent_commits`. If the cwd is not a git repo, the script returns `git_toplevel: null` and uses the cwd basename as `project_slug`.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/skills/handoff-save/scripts/collect_meta.sh"
```

### Step 2: Summarize the session
**Type**: prompt

Read the current conversation context and write the handoff body. Required sections:
- **지금까지 한 일** — concrete accomplishments this session (file paths, decisions, completed steps). Avoid vague phrases like "여러 작업을 했습니다".
- **현재 상태** — files modified but uncommitted, in-progress tasks, open questions.
- **다음 단계** — concrete next actions, prioritized.
- **이어갈 프롬프트 (복붙용)** — a self-contained prompt the user can paste into a new session. Include: project context, current branch, what was just done, the immediate next action. This is the highest-value field — make it specific enough that a fresh session can act without re-asking.

If the user passed a free-form note as argument, use it to bias the "다음 단계" and "이어갈 프롬프트" sections.

### Step 3: Preview and confirm
**Type**: review

Show the user a compact preview (frontmatter + 5 section headers + first line of each section) and ask via `AskUserQuestion`:
- "이대로 저장 (추천)"
- "다음 프롬프트만 수정"
- "전체 다시 작성"
- "취소"

Skip this step only if the user explicitly said "묻지 말고 저장" or similar.

### Step 4: Redact sensitive values
**Type**: script

Pipe the assembled markdown through `scripts/redact.py`. It masks API keys, tokens, env-var assignments, and email addresses based on common regex patterns. The script reads stdin and writes redacted markdown to stdout.

```bash
echo "$markdown" | python3 "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/skills/handoff-save/scripts/redact.py"
```

### Step 5: Write the file
**Type**: generate

1. Compute target dir: `~/.claude/handoff/{project_slug}/`. Create with `mkdir -p`.
2. Filename: `handoff-YYYYMMDD-HHmmss.md` (use local time).
3. Write the redacted markdown.
4. Update the symlink: `ln -sf {filename} ~/.claude/handoff/{project_slug}/latest.md`.
5. Report the absolute path back to the user in a single line.

## Document schema

```markdown
---
project: {project_slug}
cwd: {absolute cwd}
gitToplevel: {git rev-parse --show-toplevel or null}
branch: {current branch}
gitRemote: {origin remote URL}
gitHead: {short SHA}
savedAt: {ISO8601 with timezone}
nextPromptShort: {one-line hint, ≤ 80 chars}
---

## 프로젝트 / 브랜치
{1-2 lines}

## 지금까지 한 일
- {bullet}
- {bullet}

## 현재 상태 (수정 중 파일 / 미완 작업)
- {file path}: {what's pending}
- 미커밋 변경: {git status summary}

## 다음 단계
1. {concrete next action}
2. {concrete next action}

## 이어갈 프롬프트 (복붙용)
{Self-contained prompt that names the project, branch, current state, and asks for the next concrete action.}
```

## Settings

| Setting | Default | How to change |
|---------|---------|---------------|
| Storage root | `~/.claude/handoff/` | Edit `HANDOFF_ROOT` env var before invoking |
| Project slug | basename of git toplevel (or cwd) | Override with `HANDOFF_SLUG` env var |
| Redaction patterns | API keys, tokens, env-var assignments, emails | Edit `scripts/redact.py` |

## Why these design choices

- **Specific "이어갈 프롬프트" beats generic summaries** — the failure mode users hit most often is a vague next-step prompt. The skill makes this section mandatory and self-contained.
- **Per-project subfolder + `latest.md` symlink** — keeps the global handoff folder clean while letting `handoff-load` find the right project's most recent state in O(1).
- **Redaction before write** — handoff files live in `~/.claude/`, not git, but they may still be shared accidentally. Mask first, ask later.
- **Preview before save** — Save-time errors are cheap to fix; load-time errors corrupt the next session's premise.

## Scripts

- **`scripts/collect_meta.sh`** — Collects cwd/git metadata as JSON.
- **`scripts/redact.py`** — Masks secrets in handoff markdown.
