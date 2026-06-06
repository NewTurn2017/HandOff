---
name: handoff-save
description: This skill should be used when the user asks to "핸드오프 저장", "핸드오프 만들어줘", "여기까지 저장해줘", "세션 마무리", "다음 세션에 이어갈 수 있게 저장", "박제해줘", "wrap up session", "save handoff", "checkpoint this session", "save_handoff_road", "wcc handoff save", or any equivalent compact/checkpoint request. Use this skill whenever the user wants to capture current project state, progress, environment, risks, and a precise continuation prompt into a markdown handoff document so a future coding agent can resume without losing context.
---

# Hand-off Save

> 현재 세션의 작업 상태와 "다음에 이어갈 프롬프트"를 정교한 마크다운 핸드오프 문서로 자동 저장한다. 저장 전 확인 질문은 하지 않는다.

## When this skill applies

Trigger when the user wants to checkpoint the current session — before context fills up, end of day, model/session switch, branch/worktree switch, or any "save what we've done so far + exact next prompt" intent. Also trigger for alias-style requests such as `/save_handoff_road`, `save_handoff_road`, `wcc handoff save`, or "compact handoff".

The optional argument is a free-form note (e.g., `/handoff-save 내일은 결제 모듈부터`) that becomes the `nextPromptShort` hint and biases the priority list.

## Workflow

### Step 1: Collect session metadata
**Type**: script

Run `scripts/collect_meta.sh` from the current working directory. It returns JSON with project slug, unified handoff root, cwd, git/worktree metadata, recent commits, dirty-file count, detected coding harness, and optional test status.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-${HANDOFF_SKILL_ROOT:-$HOME/.handoff/skills}}/handoff-save/scripts/collect_meta.sh"
```

If the skill root variable is unknown, locate the installed skill directory for the active harness (`~/.claude/skills`, `~/.codex/skills`, `~/.gajae/skills`, `~/.omx/skills`, `~/.wcc/skills`) and run the script from there.

### Step 2: Summarize the session in the enhanced schema
**Type**: prompt

Read the current conversation context, tool results, todo state, git/worktree metadata, and user note. Write a handoff body with concrete file paths, exact status, and prompts that a fresh agent can execute without re-asking.

Required sections:

- **프로젝트 / 브랜치** — project name, exact cwd, git toplevel, branch, remote, HEAD, detected coding harness, and canonical handoff root.
- **진행 상황** — split into `완료된 작업`, `진행 중인 작업`, and `진행률`. Compute progress as `completed / (completed + active + known remaining)` when task counts are known; otherwise give a conservative estimate and say why.
- **현재 상태 (수정 중 파일 / 미완 작업)** — dirty files, uncommitted changes, open tasks, blocked items, and whether the worktree is clean/dirty.
- **우선순위 목록** — ordered P0/P1/P2 next actions. Each item MUST include: goal, relevant files, acceptance criteria, and a ready-to-paste prompt for the next agent.
- **특이 사항** — protected/do-not-touch files, known bugs, temporary workarounds, risky assumptions, related file list, and any user-owned changes that must not be reverted.
- **작업 환경 및 이력** — runtime/coding agent, branch, cwd, git status summary, last commit, recent commits, tests actually run and observed results, tests not run with reason.
- **이어갈 프롬프트 (복붙용)** — one self-contained prompt that names project, branch, cwd, current state, protected files, exact next action, and verification expectations.

Use the user's free-form note to set `nextPromptShort`, P0 priority, and the continuation prompt.

### Step 3: Auto-save without confirmation
**Type**: generate

Do NOT ask "이대로 저장하시겠습니까?". The default recommended action is always to redact and save immediately.

Only stop before writing if:
- the user explicitly says to preview/review first,
- required metadata cannot be collected at all,
- writing would overwrite a non-handoff file, or
- the handoff body would contain known unredacted secrets that `redact.py` cannot mask.

### Step 4: Redact sensitive values
**Type**: script

Pipe the assembled markdown through `scripts/redact.py`. It masks API keys, tokens, env-var assignments, JWTs, Bearer tokens, and common provider keys. The script reads stdin and writes redacted markdown to stdout.

```bash
printf '%s' "$markdown" | python3 "${CLAUDE_PLUGIN_ROOT:-${HANDOFF_SKILL_ROOT:-$HOME/.handoff/skills}}/handoff-save/scripts/redact.py"
```

### Step 5: Write the file
**Type**: generate

1. Compute target dir: `${HANDOFF_ROOT:-$HOME/.handoff/sessions}/{project_slug}/`.
2. Create it if needed.
3. Filename: `handoff-YYYYMMDD-HHmmss.md` using local time.
4. Write the redacted markdown.
5. Update `latest.md` symlink/copy pointer for that project.
6. Report the absolute path and whether auto-commit ran.

Use `~/.handoff/sessions` as the canonical storage path across Claude Code, Codex, Gajae Code, OMX, WCC/Whale Code, and DeepSeek-backed harnesses. `handoff-load` still reads legacy `~/.claude/handoff` files for backward compatibility.

### Step 6: Optional auto-compact commit flow
**Type**: automation design

When the active harness exposes context usage and `context_window_used >= 50%`, or when the user asks for "compact", "자동 커밋", or "auto handoff", reduce manual steps:

1. Run the normal save workflow above.
2. Consider an automatic compact commit only when ALL conditions are true:
   - the user has requested/allowed auto-compact behavior in this session or project,
   - the worktree changes are attributable to the current task and do not include protected/user-owned files,
   - no secrets are present in tracked changes or the handoff,
   - required focused verification has passed, or the handoff clearly records why verification could not run,
   - the branch is not a protected branch unless the user explicitly allows it.
3. If safe, create a small checkpoint commit with a compact message such as `chore: compact handoff checkpoint` or `chore: handoff checkpoint <slug>`.
4. Record `autoCommit: true`, commit SHA, verification command/result, and the saved handoff path in the document.
5. If any condition fails, do not commit. Record `autoCommit: skipped` and the exact skip reason.

Never fabricate context-window percentages. If the harness does not expose usage, treat the flow as manually triggered only.

## Document schema

```markdown
---
project: {project_slug}
cwd: {absolute cwd}
gitToplevel: {git rev-parse --show-toplevel or null}
branch: {current branch}
gitRemote: {origin remote URL}
gitHead: {short SHA}
runtimeAgent: {claude-code|codex-cli|gajae-code|omx|wcc-whale-deepseek|unknown}
agentHome: {detected agent home or empty}
handoffRoot: {canonical root, default ~/.handoff/sessions}
savedAt: {ISO8601 with timezone}
progressPercent: {0-100 or unknown}
worktreeStatus: {clean|dirty, N changed files}
testStatus: {passed|failed|not-run + exact command/result}
autoCommit: {true|skipped|false}
autoCommitSha: {short SHA or empty}
nextPromptShort: {one-line hint, ≤ 80 chars}
---

## 프로젝트 / 브랜치
{project, cwd, git toplevel, branch, remote, HEAD, runtime agent, handoff root}

## 진행 상황
- 진행률: {N}% ({basis})
- 완료된 작업:
  - {done item with file paths}
- 진행 중인 작업:
  - {active item with current blocker/next step}

## 현재 상태 (수정 중 파일 / 미완 작업)
- 워크트리: {clean/dirty summary}
- 미커밋 변경: {git status summary}
- 미완 작업: {open items}

## 우선순위 목록
### P0 — {title}
- 목표: {goal}
- 관련 파일: `{path}`, `{path}`
- 완료 조건: {acceptance}
- 다음 프롬프트: {ready-to-paste prompt}

### P1 — {title}
...

## 특이 사항
- 건드리면 안 되는 파일: `{path}` — {reason}
- 알려진 버그: {bug} / 임시 해결책: {workaround}
- 관련 파일: `{path}`, `{path}`
- 주의할 결정/가정: {note}

## 작업 환경 및 이력
- 런타임/에이전트: {runtimeAgent}
- 정확한 작업 경로: `{cwd}`
- 브랜치/HEAD: `{branch}` / `{gitHead}`
- 워크트리 상태: {status}
- 마지막 커밋: {last commit}
- 최근 커밋: {recent commits}
- 테스트 상태: {commands and observed results, or not run reason}

## 이어갈 프롬프트 (복붙용)
{Self-contained prompt that names the project, branch, cwd, progress, current state, protected files, next concrete action, and verification command.}
```

## Settings

| Setting | Default | How to change |
|---------|---------|---------------|
| Storage root | `~/.handoff/sessions/` | Set `HANDOFF_ROOT` env var before invoking |
| Legacy read root | `~/.claude/handoff/` | Load-side fallback only |
| Project slug | basename of git toplevel (or cwd) | Override with `HANDOFF_SLUG` env var |
| Runtime agent | auto-detected best effort | Override with `HANDOFF_AGENT` env var |
| Test status | `not recorded` | Set `HANDOFF_TEST_STATUS` or write observed test result in the handoff body |
| Redaction patterns | API keys, tokens, env-var assignments, JWTs | Edit `scripts/redact.py` |

## Why these design choices

- **No save confirmation by default** — checkpointing should be fast; the handoff file is non-destructive and timestamped.
- **Unified root across agents** — `.claude`, `.codex`, `.gajae`, `.omx`, and `.wcc` installs all read/write the same `~/.handoff/sessions` documents.
- **Specific prompts beat generic summaries** — every priority item includes a paste-ready prompt so the next agent can act immediately.
- **Redaction before write** — handoff files live outside git but may still be shared accidentally.
- **Auto-commit is guarded** — compact commits are useful, but the skill records skip reasons instead of committing unsafe or user-owned changes.

## Scripts

- **`scripts/collect_meta.sh`** — Collects cwd/git/worktree/runtime metadata as JSON.
- **`scripts/redact.py`** — Masks secrets in handoff markdown.
