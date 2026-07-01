---
name: handoff-load
description: This skill should be used when the user asks to "핸드오프 로드", "이전 세션 이어가기", "이어서 작업", "지난번 어디까지 했지", "핸드오프 불러와", "/handoff-load", "resume last session", "load handoff", "continue from last handoff", "load_handoff_road", or "wcc handoff load". Also use when the user starts a new session and wants to pick up where they left off, or when they want to review/select among multiple handoff documents instead of relying on the SessionStart auto-preview.
---

# Hand-off Load

> 현재 프로젝트(cwd 기준)의 최신 핸드오프 문서를 통합 저장소에서 찾아 진행률, 우선순위, 특이 사항, 작업 환경, 이어갈 프롬프트를 보여준다.

## When this skill applies

- 사용자가 명시적으로 핸드오프를 불러오고 싶을 때
- SessionStart hook이 미리보기를 보여줬고, 사용자가 전체 내용을 다시 로드하거나 후보를 고르고 싶을 때
- Claude Code, Codex, Gajae Code, OMX, WCC/Whale Code/DeepSeek 등 서로 다른 코딩 harness 사이에서 같은 프로젝트 상태를 이어가고 싶을 때
- 사용자가 `load_handoff_road`, `wcc handoff load`, "이어가자" 등 복원 의도를 표현할 때

자동 SessionStart 미리보기는 `scripts/load_hook.sh`가 담당한다. 이 스킬은 사용자가 직접 호출했을 때 후보 선택과 상세 복원을 담당한다.

## Workflow

### Step 1: Locate candidate handoffs
**Type**: script

Run `scripts/find_candidates.py` to list handoffs for the current project. Resolve script paths relative to this `SKILL.md` directory (`handoff-load/`) first; use installed fallback locations such as `$HOME/.handoff/skills/handoff-load` only when the skill root is unknown.

```bash
skill_root=""
for candidate in \
  "${HANDOFF_LOAD_SKILL_ROOT:-}" \
  "${HANDOFF_SKILL_ROOT:-}" \
  "${HANDOFF_SKILL_ROOT:+$HANDOFF_SKILL_ROOT/handoff-load}" \
  "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/handoff-load}" \
  "$(pwd)" \
  "$(pwd)/skills/handoff-load" \
  "$HOME/.handoff/skills/handoff-load" \
  "$HOME/.claude/skills/handoff-load" \
  "$HOME/.codex/skills/handoff-load" \
  "$HOME/.gjc/agent/skills/handoff-load" \
  "$HOME/.omx/skills/handoff-load" \
  "$HOME/.wcc/skills/handoff-load"; do
  if [ -n "$candidate" ] && [ -f "$candidate/scripts/find_candidates.py" ]; then
    skill_root="$candidate"
    break
  fi
done
if [ -z "$skill_root" ]; then
  echo "handoff-load skill root not found" >&2
  exit 1
fi
python3 "$skill_root/scripts/find_candidates.py"
```

It prints JSON: `{ "project_slug": ..., "handoff_roots": [...], "handoff_dir": ..., "candidates": [{"path", "root", "saved_at", "age_hours", "branch", "runtime_agent", "progress_percent", "next_prompt_short"}] }`. Candidates are sorted most-recent first by frontmatter `savedAt`; file mtime is used only when `savedAt` is missing or unparsable.

Default search roots:
1. `${HANDOFF_ROOT}` when set, otherwise `~/.handoff/sessions`
2. extra roots from `${HANDOFF_ROOTS}` split by OS path separator
3. legacy `~/.claude/handoff` for backward compatibility

### Step 2: Pick a handoff
**Type**: review

- 0 candidates → tell the user: "이 프로젝트에 저장된 핸드오프가 없어요. 먼저 `/handoff-save`를 실행해주세요." and stop.
- 1 candidate → use it directly.
- 2+ candidates → present a numbered list and wait for the user to choose. Each item should include age, branch, runtime agent, progress, and `next_prompt_short`. Include a cancel/skip option. If the active harness provides an interactive question tool, you may use it, but do not require a specific tool name.

If the chosen handoff is older than 7 days, ask the user to confirm before loading. For 24h+ handoffs, warn but do not block.

### Step 3: Read, validate, and summarize
**Type**: rag + prompt

1. Read the chosen file.
2. Verify cwd matches `gitToplevel` (or saved `cwd` if not a git repo). Warn on mismatch.
3. Verify current branch matches saved `branch`. Warn but proceed; cross-branch continuation may be intentional.
4. Compare saved `gitHead` with `git rev-parse --short HEAD`, and saved `worktreeStatus` with `git status --short --branch`. If either differs, summarize the saved value and current value for the user before continuing. Do not mutate the worktree.
5. Compare saved `runtimeAgent` with the current coding harness. If different, call it out clearly so the user knows the handoff moved across Claude/Codex/Gajae/OMX/WCC/DeepSeek.
6. Summarize the enhanced schema in this format:

```text
📂 [{project}] {branch} · {age} 전 저장 · {runtimeAgent}
진행률: {progressPercent}% · 워크트리: {worktreeStatus} · 테스트: {testStatus}
경로: {cwd}
파일: {path}
━━━━━━━━━━━━━━━━━━━━━━━━━━━
진행 상황:
{완료/진행 중 3-6줄}

우선순위:
1. {P0 title} — {one-line goal}
2. {P1 title} — {one-line goal}

특이 사항:
{protected files / bugs / workarounds / related files summary}

작업 환경 및 이력:
{branch, HEAD, last commit, recent commits, test status}

이어갈 프롬프트:
> {복붙용 프롬프트 그대로}
```

### Step 4: User direction
**Type**: prompt

After presenting the loaded handoff, wait for the user to accept ("ㄱㄱ", "이어가자", "continue") before executing the continuation prompt. If the user gives a new instruction instead, follow the new instruction and keep the handoff only as context.

Do NOT auto-execute the next prompt solely because a handoff was found. The save side is automatic; the load side restores context and lets the user choose the direction.

## Why these design choices

- **Unified storage prevents agent silos** — all supported coding agents read the same `~/.handoff/sessions/{project_slug}` tree.
- **Legacy fallback avoids data loss** — old `~/.claude/handoff` documents remain loadable.
- **Agent identity is visible** — loading tells the user which harness saved the handoff and whether the current harness differs.
- **Candidate listing over guessing** — wrong branch/project handoffs corrupt the next session's premise.
- **Confirmation before action** — loading context is safe; executing the saved prompt still needs user direction.

## Settings

| Setting | Default | How to change |
|---------|---------|---------------|
| Storage root | `~/.handoff/sessions/` | Set `HANDOFF_ROOT` env var |
| Additional read roots | empty | Set `HANDOFF_ROOTS` using the OS path separator |
| Legacy root | `~/.claude/handoff/` | Automatic fallback when `HANDOFF_ROOT` is not set |
| Project slug | basename of git toplevel (or cwd), normalized with `[^A-Za-z0-9._-]` → `_`, trim `_`, fallback `project` | Override with `HANDOFF_SLUG` env var |
| Runtime agent | best-effort from frontmatter/current env | Override save-side with `HANDOFF_AGENT` |
| Stale threshold (warn) | 24 hours | Edit `STALE_WARN_HOURS` in `scripts/find_candidates.py` |
| Stale threshold (require confirm) | 7 days | Edit `STALE_BLOCK_HOURS` in `scripts/find_candidates.py` |

## Scripts

- **`scripts/find_candidates.py`** — Lists handoff candidates for the current project across canonical and legacy roots.
- **`scripts/load_hook.sh`** — SessionStart hook entry point. Outputs a dry-run preview to stdout as hook JSON. Designed to silent-fail and always exit 0.

## SessionStart hook setup

`install.sh --hook` registers `scripts/load_hook.sh` in every selected Claude-compatible settings file whose skill directory exists, including Claude Code, Gajae Code, OMX, and WCC when their directories are present.

Example hook block:

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

The hook computes the project slug from cwd, searches fresh handoffs (≤7 days), prints progress/priority preview plus the continuation prompt, and never blocks session startup.
