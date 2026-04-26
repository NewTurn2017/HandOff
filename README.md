# HandOff

> Claude Code & Codex CLI 세션을 마크다운 한 장으로 박제(save)하고, 다음 세션에서 그대로 이어가는(load) 한 쌍의 스킬.

세션이 길어지면 컨텍스트 윈도우가 차거나, 모델/세션을 갈아엎거나, 그냥 하루를 마무리해야 한다. 그때마다 "어디까지 했더라"를 손으로 다시 정리하는 대신 **`/handoff-save`** 한 번으로 현재 상태와 *다음에 붙여넣을 프롬프트*까지 마크다운으로 떨어뜨리고, 새 세션에서 **`/handoff-load`**(또는 SessionStart 훅의 자동 미리보기)로 그대로 이어간다.

이 레포는 두 스킬의 **단일 출처(single source of truth)**다. `install.sh`가 `~/.claude/skills/`와 `~/.codex/skills/` 양쪽에 심볼릭 링크를 걸어주므로, 여기에서 한 번 수정하면 Claude Code와 Codex CLI 양쪽에 즉시 반영된다.

---

## TL;DR — 한 줄 설치

```bash
git clone https://github.com/NewTurn2017/HandOff.git ~/dev/HandOff && \
  cd ~/dev/HandOff && ./install.sh --hook
```

검증:

```bash
ls -l ~/.claude/skills/handoff-save ~/.claude/skills/handoff-load \
       ~/.codex/skills/handoff-save  ~/.codex/skills/handoff-load
```

네 줄 모두 이 레포 경로로 가는 심링크면 끝. Claude Code/Codex를 새로 띄우고 `/handoff-save` 또는 "핸드오프 저장해줘"를 호출하면 동작한다.

---

## AI 에이전트용 설치 가이드

새로운 머신에서 AI 에이전트가 이 README만 보고 설치를 끝낼 수 있도록 명령을 그대로 적어둔다. **모든 명령은 idempotent** — 이미 설치되어 있으면 아무 것도 깨뜨리지 않고 통과한다.

### 사전 조건

- `git`, `bash`, `python3 ≥ 3.8`이 PATH에 있어야 한다.
- Claude Code를 쓴다면 `~/.claude/skills/` 디렉터리, Codex CLI를 쓴다면 `~/.codex/skills/` 디렉터리가 존재해야 한다. 없는 쪽은 자동으로 스킵된다.

### 설치 순서

```bash
# 1. 클론 (위치는 자유. 영구 보관할 곳을 권장)
git clone https://github.com/NewTurn2017/HandOff.git ~/dev/HandOff
cd ~/dev/HandOff

# 2. 심링크 설치 (+ SessionStart 훅 등록)
./install.sh --hook

# 3. 검증
ls -l ~/.claude/skills/handoff-save ~/.claude/skills/handoff-load 2>/dev/null
ls -l ~/.codex/skills/handoff-save  ~/.codex/skills/handoff-load  2>/dev/null
bash skills/handoff-save/scripts/collect_meta.sh        # JSON 출력되면 OK
python3 skills/handoff-load/scripts/find_candidates.py  # JSON 출력되면 OK
```

### `install.sh`가 하는 일

1. `~/.claude/skills/handoff-{save,load}` → 이 레포의 `skills/handoff-{save,load}`로 심링크.
2. `~/.codex/skills/handoff-{save,load}` → 동일하게 심링크.
3. 같은 이름의 **실제 폴더/파일**이 이미 있으면 `*.backup-YYYYMMDD-HHmmss`로 백업한 뒤 링크로 교체. 같은 경로를 가리키는 심링크가 이미 있으면 그대로 둔다.
4. `--hook`을 주면 `~/.claude/settings.json`에 SessionStart 훅을 idempotent하게 추가한다 (`scripts/register_session_hook.py`).

### 옵션

```bash
./install.sh                # ~/.claude/skills + ~/.codex/skills 양쪽 (훅은 등록 안 함)
./install.sh --hook         # 위 + SessionStart 훅 등록
./install.sh --claude       # ~/.claude/skills 만
./install.sh --codex        # ~/.codex/skills 만
./install.sh --uninstall    # 이 레포가 만든 심링크만 제거 (백업 폴더는 그대로 둠)
```

### 백업 폴더 정리

기존에 진짜 폴더로 깔려 있던 스킬이 있었다면 `*.backup-YYYYMMDD-HHmmss`로 옮겨진다. 이 레포 내용과 동일하다는 게 확인되면 안전하게 삭제 가능:

```bash
diff -r ~/.claude/skills/handoff-save.backup-* skills/handoff-save && \
  rm -rf ~/.claude/skills/handoff-save.backup-* ~/.claude/skills/handoff-load.backup-*
diff -r ~/.codex/skills/handoff-save.backup-*  skills/handoff-save && \
  rm -rf ~/.codex/skills/handoff-save.backup-*  ~/.codex/skills/handoff-load.backup-*
```

### 업데이트

```bash
cd ~/dev/HandOff && git pull
```

심링크는 그대로이므로 추가 작업 불필요. SKILL.md/스크립트 변경이 즉시 반영된다.

### 제거

```bash
cd ~/dev/HandOff && ./install.sh --uninstall
```

훅을 제거하려면 `~/.claude/settings.json`의 `hooks.SessionStart`에서 `handoff-load/scripts/load_hook.sh`를 가리키는 항목을 직접 지운다.

---

## 두 스킬 개요

### `handoff-save` — 세션 박제

- **트리거 (한국어)**: "핸드오프 저장", "박제해줘", "여기까지 저장", "세션 마무리", "다음 세션에 이어갈 수 있게 저장"
- **트리거 (영어)**: `/handoff-save`, "save handoff", "wrap up session", "checkpoint this session"
- **선택 인자**: `/handoff-save <한 줄 메모>` — `nextPromptShort` 힌트로 들어간다.
- **수집**: cwd / git toplevel / 브랜치 / origin URL / HEAD short SHA / 미커밋 파일 수 / 최근 커밋 3개
- **요약 섹션**: 지금까지 한 일 / 현재 상태(미커밋·미완) / 다음 단계 / **이어갈 프롬프트(복붙용)**
- **자동 마스킹**: API 키(`sk-…`, `pk_…`), GitHub 토큰(`ghp_…`/`gho_…`), Slack 토큰(`xox[baprs]-…`), AWS(`AKIA…`), Google(`AIza…`), Bearer, JWT, `*_KEY=` / `*_TOKEN=` / `*_SECRET=` / `*_PASSWORD=` 류 env 값
- **저장 위치**: `~/.claude/handoff/{project_slug}/handoff-YYYYMMDD-HHmmss.md` + `latest.md` 심링크

### `handoff-load` — 세션 복원

- **트리거 (한국어)**: "핸드오프 로드", "이어가자", "지난번 어디까지 했지", "이어서 작업"
- **트리거 (영어)**: `/handoff-load`, "resume last session", "load handoff", "continue from last handoff"
- **후보 처리**: 0개 → 안내 / 1개 → 그대로 / 2+개 → `AskUserQuestion`로 선택지 제시
- **신선도**: ≥24h → 경고, ≥7d → 명시적 확인 요구
- **자동 실행 안 함**: 컨텍스트만 복원하고 사용자가 수락("ㄱㄱ", "이어가자")해야 다음 단계로 넘어간다.
- **SessionStart 훅** *(선택)*: 새 세션이 뜰 때 7일 이내 핸드오프가 있으면 5줄 미리보기를 추가 컨텍스트로 주입한다.

스킬 본문은 [`skills/handoff-save/SKILL.md`](skills/handoff-save/SKILL.md), [`skills/handoff-load/SKILL.md`](skills/handoff-load/SKILL.md) 참고.

---

## 레포 구조

```
HandOff/
├── README.md
├── LICENSE                          # MIT
├── install.sh                       # 심링크 설치/제거 + 훅 등록
├── scripts/
│   └── register_session_hook.py     # ~/.claude/settings.json에 SessionStart 훅 idempotent 등록
└── skills/
    ├── handoff-save/
    │   ├── SKILL.md                 # 워크플로우 (트리거/단계/스키마/근거)
    │   └── scripts/
    │       ├── collect_meta.sh      # cwd·git 메타데이터 → JSON
    │       └── redact.py            # 시크릿 마스킹 (stdin → stdout)
    └── handoff-load/
        ├── SKILL.md
        └── scripts/
            ├── find_candidates.py   # 프로젝트 슬러그로 핸드오프 후보 나열 (JSON)
            └── load_hook.sh         # SessionStart 훅 본체 (silent-fail, 항상 exit 0)
```

핸드오프 *문서* 자체는 이 레포에 들어가지 않는다 — 작업 결과물은 `~/.claude/handoff/{project_slug}/`에 쌓이고, 깃 추적 대상이 아니다.

---

## 핸드오프 문서 스키마

```markdown
---
project: my-project
cwd: /Users/me/dev/my-project
gitToplevel: /Users/me/dev/my-project
branch: feat/payments
gitRemote: https://github.com/me/my-project.git
gitHead: a1b2c3d
savedAt: 2026-04-26T22:14:31+09:00
nextPromptShort: 결제 모듈 webhook 검증부터
---

## 프로젝트 / 브랜치
…

## 지금까지 한 일
- …

## 현재 상태 (수정 중 파일 / 미완 작업)
- …

## 다음 단계
1. …

## 이어갈 프롬프트 (복붙용)
> …
```

`이어갈 프롬프트`가 핵심 산출물이다. 새 세션에 그대로 붙여넣었을 때 추가 질문 없이 바로 일을 이어갈 수 있을 만큼 자기완결적이어야 한다.

---

## SessionStart 훅 상세

`install.sh --hook`을 실행하면 `~/.claude/settings.json`에 다음 블록이 idempotent하게 추가된다:

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

훅은 항상 `exit 0` — 어떤 이유로든 실패해도 세션 시작을 막지 않는다. 7일을 넘긴 핸드오프는 미리보기에서 자동 제외된다.

---

## 환경 변수

| 변수 | 기본값 | 효과 |
|------|--------|------|
| `HANDOFF_ROOT` | `~/.claude/handoff` | 핸드오프 파일 저장 루트 |
| `HANDOFF_SLUG` | git toplevel basename (없으면 cwd basename) | 프로젝트 슬러그 강제 지정 (워크트리 등에서 유용) |
| `CLAUDE_SKILLS_DIR` | `~/.claude/skills` | `install.sh`가 링크할 Claude Code 스킬 디렉터리 |
| `CODEX_SKILLS_DIR` | `~/.codex/skills` | `install.sh`가 링크할 Codex 스킬 디렉터리 |
| `CLAUDE_SETTINGS` | `~/.claude/settings.json` | `register_session_hook.py`가 수정할 settings 파일 |

---

## 개발 워크플로우

이 레포가 Claude Code/Codex 양쪽이 실제로 로드하는 파일의 단일 출처이므로, 별도 빌드/배포가 없다.

1. `skills/handoff-*/SKILL.md` 또는 `skills/handoff-*/scripts/*`를 수정한다.
2. 수정한 그 순간 `~/.claude/skills/handoff-*`와 `~/.codex/skills/handoff-*`에 즉시 반영된다 (심링크).
3. 새 Claude Code/Codex 세션을 띄워 변경 동작을 확인한다.
4. 커밋 & 푸시.

### 수동 스모크 테스트

```bash
# 1. cwd/git 메타데이터 수집
bash skills/handoff-save/scripts/collect_meta.sh | jq

# 2. 시크릿 마스킹
echo 'TEST_API_KEY=sk-abcdefghijklmnopqrstuvwx' | python3 skills/handoff-save/scripts/redact.py

# 3. 후보 조회
python3 skills/handoff-load/scripts/find_candidates.py | jq

# 4. SessionStart 훅 dry-run (현재 cwd에 핸드오프가 있어야 출력됨)
echo '{}' | bash skills/handoff-load/scripts/load_hook.sh
```

---

## 라이선스

MIT — [LICENSE](LICENSE) 참고.

설계·구현: [@NewTurn2017](https://github.com/NewTurn2017). Anthropic Claude Code Skills 포맷 기반.
