# HandOff

> Claude Code & Codex 세션을 마크다운 한 장으로 박제(save)하고, 다음 세션에서 그대로 이어가는(load) 한 쌍의 스킬.

세션이 길어지면 컨텍스트 윈도우가 차거나, 모델/세션을 갈아엎거나, 그냥 하루를 마무리해야 한다. 그때마다 "어디까지 했더라"를 손으로 다시 정리하는 대신, **`/handoff-save`** 한 번으로 현재 상태와 *다음에 붙여넣을 프롬프트*까지 마크다운으로 떨어뜨리고, 새 세션에서 **`/handoff-load`**(또는 SessionStart 훅의 자동 미리보기)로 그대로 이어가자.

이 레포는 두 스킬의 단일 출처(single source of truth)다. `install.sh`가 `~/.claude/skills/`와 `~/.codex/skills/` 양쪽에 심볼릭 링크를 걸어주므로, 여기에서 한 번 수정하면 Claude Code와 Codex CLI 양쪽에 즉시 반영된다.

---

## 무엇을 하는 스킬인가

### `handoff-save`
현재 세션을 마크다운 핸드오프 문서 한 장으로 저장한다.

- **트리거**: "핸드오프 저장", "박제해줘", "여기까지 저장", "세션 마무리", `/handoff-save`, "save handoff", "checkpoint this session" 등
- **수집하는 정보**: cwd, git toplevel, 브랜치, origin URL, HEAD short SHA, 미커밋 파일 수, 최근 커밋 3개
- **요약 섹션**: 지금까지 한 일 / 현재 상태(미커밋·미완) / 다음 단계 / **이어갈 프롬프트(복붙용)**
- **자동 마스킹**: API 키, GitHub/Slack 토큰, AWS·Google 키, Bearer 토큰, JWT, `*_KEY=`/`*_TOKEN=`/`*_SECRET=` 류 환경변수 값
- **출력 위치**: `~/.claude/handoff/{project_slug}/handoff-YYYYMMDD-HHmmss.md` + `latest.md` 심볼릭 링크

### `handoff-load`
현재 cwd가 속한 프로젝트의 가장 최신 핸드오프를 찾아 요약하고, 이어갈 프롬프트를 그대로 보여준다.

- **트리거**: "핸드오프 로드", "이어가자", "지난번 어디까지 했지", `/handoff-load`, "resume last session" 등
- **후보 처리**: 0개 → 안내, 1개 → 그대로 사용, 2개+ → `AskUserQuestion`으로 선택
- **신선도 체크**: 24시간 이상이면 경고, 7일 이상이면 명시적 확인 요구
- **자동 실행 안 함**: 컨텍스트만 복원하고 사용자가 수락("ㄱㄱ" 등)했을 때만 다음 단계로 진행
- **SessionStart 훅** *(선택)*: 새 세션 시작 시 7일 이내 핸드오프가 있으면 5줄 미리보기를 컨텍스트로 주입한다.

두 스킬의 풀 워크플로우는 [`skills/handoff-save/SKILL.md`](skills/handoff-save/SKILL.md), [`skills/handoff-load/SKILL.md`](skills/handoff-load/SKILL.md)에 정의되어 있다.

---

## 레포 구조

```
HandOff/
├── README.md
├── install.sh                       # ~/.claude/skills, ~/.codex/skills 심볼릭 링크 설치/제거
├── scripts/
│   └── register_session_hook.py     # ~/.claude/settings.json 에 SessionStart 훅 등록 (idempotent)
└── skills/
    ├── handoff-save/
    │   ├── SKILL.md
    │   └── scripts/
    │       ├── collect_meta.sh      # cwd/git 메타데이터를 JSON으로 출력
    │       └── redact.py            # 시크릿 마스킹 (stdin → stdout)
    └── handoff-load/
        ├── SKILL.md
        └── scripts/
            ├── find_candidates.py   # 프로젝트 슬러그로 핸드오프 후보 나열
            └── load_hook.sh         # SessionStart 훅 본체 (silent-fail)
```

핸드오프 *문서* 자체는 이 레포에 들어가지 않는다 — 작업 결과물은 사용자 홈의 `~/.claude/handoff/{project_slug}/`에 쌓이고, 깃에 들어가지 않는다.

---

## 설치

### 1. 클론

```bash
git clone https://github.com/NewTurn2017/HandOff.git
cd HandOff
```

### 2. 심볼릭 링크 설치

```bash
./install.sh
```

기본 동작:
- `~/.claude/skills/handoff-save`, `~/.claude/skills/handoff-load` → 이 레포의 `skills/handoff-*`로 심링크
- `~/.codex/skills/handoff-save`, `~/.codex/skills/handoff-load` → 동일하게 심링크
- 이미 같은 이름의 폴더/링크가 있으면 자동으로 `*.backup-YYYYMMDD-HHmmss`로 백업한 뒤 링크로 교체

옵션:

```bash
./install.sh --claude       # Claude Code만
./install.sh --codex        # Codex만
./install.sh --hook         # SessionStart 훅까지 ~/.claude/settings.json에 등록
./install.sh --uninstall    # 이 레포가 만든 심링크만 제거 (백업은 그대로 둠)
```

### 3. 검증

```bash
ls -l ~/.claude/skills/handoff-* ~/.codex/skills/handoff-*
```

세 줄 모두 이 레포 경로를 가리키면 OK.

---

## SessionStart 훅 (선택)

`handoff-load`는 사용자가 호출하는 수동 경로고, **자동 미리보기**는 `~/.claude/settings.json`의 SessionStart 훅으로 동작한다. `install.sh --hook`을 쓰면 다음 블록을 idempotent하게 추가한다:

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

훅은 항상 `exit 0` 으로 끝난다 — 어떤 이유로든 실패해도 세션 시작을 막지 않는다.

---

## 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `HANDOFF_ROOT` | `~/.claude/handoff` | 핸드오프 파일 저장 루트 |
| `HANDOFF_SLUG` | git toplevel basename (또는 cwd basename) | 프로젝트 슬러그 강제 지정 |
| `CLAUDE_SKILLS_DIR` | `~/.claude/skills` | `install.sh`가 링크할 Claude Code 스킬 디렉터리 |
| `CODEX_SKILLS_DIR` | `~/.codex/skills` | `install.sh`가 링크할 Codex 스킬 디렉터리 |
| `CLAUDE_SETTINGS` | `~/.claude/settings.json` | `register_session_hook.py`가 수정할 settings 파일 |

여러 워크트리/디렉터리가 같은 프로젝트로 묶여야 한다면 `HANDOFF_SLUG`를 셸에 export 해두는 게 가장 단순하다.

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

`이어갈 프롬프트` 섹션이 핵심 산출물이다 — 새 세션에서 그대로 붙여넣었을 때 추가 질문 없이 바로 일을 이어갈 수 있을 만큼 자기완결적이어야 한다.

---

## 개발

이 레포가 Claude Code/Codex 양쪽이 실제로 로드하는 파일의 단일 출처이므로, 별도 빌드/배포 단계가 없다. 워크플로우:

1. `skills/handoff-save/SKILL.md`나 `skills/handoff-*/scripts/*`를 수정한다.
2. 수정한 그 순간 `~/.claude/skills/handoff-*`와 `~/.codex/skills/handoff-*`에 즉시 반영된다 (심링크).
3. 새 Claude Code/Codex 세션을 띄워 변경 동작을 확인한다.
4. 커밋 & 푸시.

스킬 작성 가이드에 맞추고 싶다면 `superpowers:writing-skills` 스킬과 [Anthropic Skills 문서](https://docs.claude.com/en/api/agent-skills/skill)를 참고하자.

### 수동 테스트

```bash
# meta 수집
bash skills/handoff-save/scripts/collect_meta.sh | jq

# redact
echo 'TEST_API_KEY=sk-abcdefghijklmnopqrstuvwx' | python3 skills/handoff-save/scripts/redact.py

# 후보 조회
python3 skills/handoff-load/scripts/find_candidates.py | jq

# 훅 dry-run (cwd가 핸드오프가 있는 프로젝트여야 함)
echo '{}' | bash skills/handoff-load/scripts/load_hook.sh
```

---

## 라이선스

MIT.

## Credits

설계·구현: [@NewTurn2017](https://github.com/NewTurn2017). Claude Code skills 포맷에 맞춰 작성.
