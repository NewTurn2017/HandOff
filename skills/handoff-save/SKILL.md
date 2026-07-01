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

Run `scripts/collect_meta.sh` from the current working directory. Resolve script paths relative to this `SKILL.md` directory (`handoff-save/`) first; use installed fallback locations such as `$HOME/.handoff/skills/handoff-save` only when the skill root is unknown. It returns JSON with project slug, unified handoff root, cwd, git/worktree metadata, recent commits, dirty-file count, detected coding harness, and optional test status.

```bash
skill_root=""
for candidate in \
  "${HANDOFF_SAVE_SKILL_ROOT:-}" \
  "${HANDOFF_SKILL_ROOT:-}" \
  "${HANDOFF_SKILL_ROOT:+$HANDOFF_SKILL_ROOT/handoff-save}" \
  "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/handoff-save}" \
  "$(pwd)" \
  "$(pwd)/skills/handoff-save" \
  "$HOME/.handoff/skills/handoff-save" \
  "$HOME/.claude/skills/handoff-save" \
  "$HOME/.codex/skills/handoff-save" \
  "$HOME/.gjc/agent/skills/handoff-save" \
  "$HOME/.omx/skills/handoff-save" \
  "$HOME/.wcc/skills/handoff-save"; do
  if [ -n "$candidate" ] && [ -f "$candidate/scripts/collect_meta.sh" ]; then
    skill_root="$candidate"
    break
  fi
done
if [ -z "$skill_root" ]; then
  echo "handoff-save skill root not found" >&2
  exit 1
fi
bash "$skill_root/scripts/collect_meta.sh"
```

If the harness exposes the path of this `SKILL.md`, set `HANDOFF_SAVE_SKILL_ROOT` to its directory and the code block above will use that as the first source of truth.

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

Pipe the assembled markdown through `scripts/redact.py`. Resolve `scripts/redact.py` from the same `skill_root` directory as this `SKILL.md`; fall back to installed locations only when that directory is unknown. It masks API keys, tokens, env-var assignments, JWTs, Bearer tokens, and common provider keys. The script reads stdin and writes redacted markdown to stdout.

```bash
skill_root=""
for candidate in \
  "${HANDOFF_SAVE_SKILL_ROOT:-}" \
  "${HANDOFF_SKILL_ROOT:-}" \
  "${HANDOFF_SKILL_ROOT:+$HANDOFF_SKILL_ROOT/handoff-save}" \
  "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/handoff-save}" \
  "$(pwd)" \
  "$(pwd)/skills/handoff-save" \
  "$HOME/.handoff/skills/handoff-save" \
  "$HOME/.claude/skills/handoff-save" \
  "$HOME/.codex/skills/handoff-save" \
  "$HOME/.gjc/agent/skills/handoff-save" \
  "$HOME/.omx/skills/handoff-save" \
  "$HOME/.wcc/skills/handoff-save"; do
  if [ -n "$candidate" ] && [ -f "$candidate/scripts/redact.py" ]; then
    skill_root="$candidate"
    break
  fi
done
if [ -z "$skill_root" ]; then
  echo "handoff-save skill root not found" >&2
  exit 1
fi
printf '%s' "$markdown" | python3 "$skill_root/scripts/redact.py"
```

### Step 5: Write the file
**Type**: generate

Use the same deterministic file write sequence in every harness. `metadata_json` is the JSON emitted by `collect_meta.sh`, and `markdown` is the assembled handoff markdown before redaction.

```bash
set -euo pipefail

: "${metadata_json:?metadata_json from collect_meta.sh is required}"
: "${markdown:?assembled handoff markdown is required}"

skill_root=""
for candidate in \
  "${HANDOFF_SAVE_SKILL_ROOT:-}" \
  "${HANDOFF_SKILL_ROOT:-}" \
  "${HANDOFF_SKILL_ROOT:+$HANDOFF_SKILL_ROOT/handoff-save}" \
  "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/handoff-save}" \
  "$(pwd)" \
  "$(pwd)/skills/handoff-save" \
  "$HOME/.handoff/skills/handoff-save" \
  "$HOME/.claude/skills/handoff-save" \
  "$HOME/.codex/skills/handoff-save" \
  "$HOME/.gjc/agent/skills/handoff-save" \
  "$HOME/.omx/skills/handoff-save" \
  "$HOME/.wcc/skills/handoff-save"; do
  if [ -n "$candidate" ] && [ -f "$candidate/scripts/redact.py" ]; then
    skill_root="$candidate"
    break
  fi
done
if [ -z "$skill_root" ]; then
  echo "handoff-save skill root not found" >&2
  exit 1
fi

project_slug=$(printf '%s' "$metadata_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["project_slug"])')
handoff_root=$(printf '%s' "$metadata_json" | python3 -c 'import json,os,sys; print(json.load(sys.stdin).get("handoff_root") or os.path.expanduser("~/.handoff/sessions"))')
target_dir="${handoff_root%/}/$project_slug"
timestamp="$(date +%Y%m%d-%H%M%S)"
target_file="$target_dir/handoff-$timestamp.md"
tmp_file="$target_file.tmp"

mkdir -p "$target_dir"
trap 'rm -f "$tmp_file"' EXIT
printf '%s' "$markdown" | python3 "$skill_root/scripts/redact.py" > "$tmp_file"
mv "$tmp_file" "$target_file"
printf '%s\n' "$target_file"
```

The filename pattern is always `handoff-YYYYMMDD-HHmmss.md` using local time. Report the absolute saved path.

Use `~/.handoff/sessions` as the canonical storage path across Claude Code, Codex, Gajae Code, OMX, WCC/Whale Code, and DeepSeek-backed harnesses. `handoff-load` still reads legacy `~/.claude/handoff` files for backward compatibility.

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
| Project slug | basename of git toplevel (or cwd), normalized with `[^A-Za-z0-9._-]` → `_`, trim `_`, fallback `project` | Override with `HANDOFF_SLUG` env var |
| Runtime agent | auto-detected best effort | Override with `HANDOFF_AGENT` env var |
| Test status | `not recorded` | Set `HANDOFF_TEST_STATUS` or write observed test result in the handoff body |
| Redaction patterns | API keys, tokens, env-var assignments, JWTs | Edit `scripts/redact.py` |

## Why these design choices

- **No save confirmation by default** — checkpointing should be fast; the handoff file is non-destructive and timestamped.
- **Unified root across agents** — `.claude`, `.codex`, `.gjc/agent`, `.omx`, and `.wcc` installs all read/write the same `~/.handoff/sessions` documents.
- **Specific prompts beat generic summaries** — every priority item includes a paste-ready prompt so the next agent can act immediately.
- **Redaction before write** — handoff files live outside git but may still be shared accidentally.

## Scripts

- **`scripts/collect_meta.sh`** — Collects cwd/git/worktree/runtime metadata as JSON.
- **`scripts/redact.py`** — Masks secrets in handoff markdown.
