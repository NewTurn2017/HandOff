# HandOff

> Claude Code, Codex CLI, Gajae Code, OMX, WCC/Whale Code(DeepSeek) 세션을 하나의 통합 저장소에 저장(save)하고 다음 세션에서 이어가는(load) 스킬 세트.

세션이 길어지거나 모델/코딩 harness를 바꿀 때마다 현재 상태를 다시 설명하지 않도록 **`/handoff-save`** 한 번으로 진행률, 작업 이력, 우선순위, 주의 파일, 테스트 상태, 이어갈 프롬프트를 마크다운으로 저장한다. 새 세션에서는 **`/handoff-load`** 또는 SessionStart 훅 미리보기로 같은 상태를 복원한다.

핸드오프 문서는 모든 agent가 공유하는 기본 경로 **`~/.handoff/sessions/{project_slug}/`**에 저장된다. 예전 버전의 `~/.claude/handoff/{project_slug}/` 문서도 load 쪽에서 계속 읽는다.

---

## TL;DR — 설치

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/NewTurn2017/HandOff/main/bootstrap.sh | bash
```

SessionStart 훅까지 함께 등록:

```bash
curl -fsSL https://raw.githubusercontent.com/NewTurn2017/HandOff/main/bootstrap.sh | bash -s -- --hook
```

### Windows (PowerShell)

```powershell
iwr -useb https://raw.githubusercontent.com/NewTurn2017/HandOff/main/bootstrap.ps1 | iex
```

훅 포함:

```powershell
$env:HANDOFF_HOOK=1; iwr -useb https://raw.githubusercontent.com/NewTurn2017/HandOff/main/bootstrap.ps1 | iex
```

설치 후 새 coding-agent 세션에서 다음 중 하나로 저장한다.

```text
# Claude/Codex/OMX/WCC 스타일 direct command
/handoff-save
/save_handoff_road

# Gajae Code/GJC native skill command
/skill:handoff-save

# 자연어 트리거
핸드오프 저장해줘
wcc handoff save
```

GJC는 공식적으로 skill을 `/skill:<name>` 형태로 호출한다. 편의를 위해 installer가 `~/.gjc/agent/commands/`에 `/handoff-save`, `/handoff-load`, `/save_handoff_road`, `/load_handoff_road` wrapper command도 함께 설치한다.

---

## 지원 환경과 설치 위치

`install.sh`는 존재하는 skill 디렉터리에 심볼릭 링크를 만든다. Gajae/GJC는 공식 경로인 `~/.gjc/agent/skills`와 command wrapper 경로 `~/.gjc/agent/commands`를 사용한다.

| Agent / alias | 기본 skill 경로 | hook settings |
|---|---|---|
| Claude Code | `~/.claude/skills` | `~/.claude/settings.json` |
| Codex CLI | `~/.codex/skills` | 없음 |
| Gajae Code / GJC | `~/.gjc/agent/skills` | `~/.gjc/agent/settings.json` |
| OMX | `~/.omx/skills` | `~/.omx/settings.json` |
| WCC / Whale Code / DeepSeek | `~/.wcc/skills` | `~/.wcc/settings.json` |

설치되는 skill 이름과 command alias:

- skill: `handoff-save`, `handoff-load`
- GJC native command wrapper: `/handoff-save`, `/handoff-load`, `/save_handoff_road`, `/load_handoff_road`
- GJC canonical skill invocation: `/skill:handoff-save`, `/skill:handoff-load`

수동 설치:

```bash
git clone https://github.com/NewTurn2017/HandOff.git ~/.handoff
cd ~/.handoff
./install.sh --hook
```

대상 제한:

```bash
./install.sh --claude
./install.sh --codex
./install.sh --gajae
./install.sh --omx
./install.sh --wcc
./install.sh --uninstall
```

---

## 핵심 변경점

### 저장 확인 단계 제거

`handoff-save`는 더 이상 매번 "이대로 저장하시겠습니까?"를 묻지 않는다. 기본 추천 경로는 즉시 저장이다. 사용자가 명시적으로 preview/review를 요청하거나, 저장이 위험한 상태(메타데이터 수집 실패, 알려진 미마스킹 secret 등)일 때만 멈춘다.

### 상세한 handoff 문서

저장 문서는 다음 정보를 필수로 포함한다.

- **진행 상황**: 완료된 작업, 진행 중인 작업, 진행률(%), 산정 근거
- **현재 상태**: 수정 중 파일, 미완 작업, 워크트리 clean/dirty 상태
- **우선순위 목록**: P0/P1/P2 다음 작업, 관련 파일, 완료 조건, 바로 붙여넣을 프롬프트
- **특이 사항**: 건드리면 안 되는 파일, 현재 버그, 임시 해결책, 관련 파일, 위험한 가정
- **작업 환경 및 이력**: coding harness, cwd, git toplevel, branch, remote, HEAD, 마지막 커밋, 최근 커밋, 테스트 결과
- **이어갈 프롬프트**: 새 세션에 그대로 붙여넣으면 즉시 이어갈 수 있는 자기완결 프롬프트

### 통합 저장소와 agent 판별

기본 저장소는 agent별 dotdir가 아니라 `~/.handoff/sessions`다.

```text
~/.handoff/sessions/{project_slug}/handoff-YYYYMMDD-HHmmss.md
~/.handoff/sessions/{project_slug}/latest.md
```

`collect_meta.sh`는 저장 시점의 runtime agent를 best-effort로 기록한다.

- 명시 override: `HANDOFF_AGENT=gajae-code /hand-off-save`
- 자동 감지 후보: `claude-code`, `codex-cli`, `gajae-code`, `omx`, `wcc-whale-deepseek`, `unknown`
- load 시 저장 agent와 현재 agent가 다르면 경고해서 Claude/Codex/Gajae/OMX/WCC 사이 이동을 명확히 보여준다.

### 자동 compact / commit 설계

context 사용량이 50% 이상임을 harness가 제공하거나, 사용자가 "compact", "자동 커밋", "auto handoff"를 요청하면 `handoff-save`는 자동 저장 흐름을 우선한다.

자동 checkpoint commit은 다음 조건이 모두 참일 때만 수행하도록 설계되어 있다.

1. 사용자 또는 프로젝트가 auto-compact를 허용했다.
2. 변경 사항이 현재 작업 범위이며 protected/user-owned 파일을 포함하지 않는다.
3. secret이 추적 변경이나 handoff에 남아 있지 않다.
4. 필요한 focused verification이 통과했거나, 실행하지 못한 이유가 handoff에 기록된다.
5. protected branch가 아니거나 사용자가 허용했다.

조건이 하나라도 실패하면 commit하지 않고 handoff에 `autoCommit: skipped`와 이유를 기록한다.

---

## 두 스킬 개요

### `handoff-save` — 세션 저장

- **트리거(한국어)**: "핸드오프 저장", "박제해줘", "여기까지 저장", "세션 마무리", "다음 세션에 이어갈 수 있게 저장"
- **트리거(영어/alias)**: `/handoff-save`, `/save_handoff_road`, `save_handoff_road`, `wcc handoff save`, "save handoff", "wrap up session", "checkpoint this session"
- **수집**: cwd, git toplevel, branch, remote, HEAD, worktree 상태, 최근 커밋, 마지막 커밋, runtime agent, 테스트 상태
- **저장 위치**: `${HANDOFF_ROOT:-$HOME/.handoff/sessions}/{project_slug}/`
- **자동 마스킹**: API key, GitHub/Slack/AWS/Google token, Bearer, JWT, `*_KEY`, `*_TOKEN`, `*_SECRET`, `*_PASSWORD`류 env 값

### `handoff-load` — 세션 복원

- **트리거(한국어)**: "핸드오프 로드", "이어가자", "지난번 어디까지 했지", "이어서 작업"
- **트리거(영어/alias)**: `/handoff-load`, `/load_handoff_road`, `load_handoff_road`, `wcc handoff load`, "resume last session", "continue from last handoff"
- **후보 처리**: 0개 → 안내 / 1개 → 그대로 / 2+개 → 선택지 제시
- **검색 경로**: `HANDOFF_ROOT` 또는 `~/.handoff/sessions`, `HANDOFF_ROOTS`, legacy `~/.claude/handoff`
- **신선도**: ≥24h 경고, ≥7d 명시적 확인
- **자동 실행 안 함**: load는 context만 복원한다. 사용자가 "ㄱㄱ", "이어가자" 등으로 진행 방향을 확인해야 실행한다.

---

## 레포 구조

```text
HandOff/
├── README.md
├── AGENTS.md                         # AI assistant repository guidance
├── LICENSE                           # MIT
├── bootstrap.sh                      # macOS/Linux bootstrap
├── bootstrap.ps1                     # Windows bootstrap
├── install.sh                        # skill 링크/제거 + hook 등록
├── scripts/
│   └── register_session_hook.py      # Claude-compatible SessionStart hook 등록
└── skills/
    ├── handoff-save/
    │   ├── SKILL.md                  # 저장 workflow / schema / auto-compact 규칙
    │   └── scripts/
    │       ├── collect_meta.sh       # cwd·git·runtime metadata → JSON
    │       └── redact.py             # secret masking (stdin → stdout)
    └── handoff-load/
        ├── SKILL.md                  # 복원 workflow / 후보 선택 / agent mismatch 안내
        └── scripts/
            ├── find_candidates.py    # 통합/legacy root 후보 나열 (JSON)
            └── load_hook.sh          # SessionStart hook 본체 (silent-fail, exit 0)
```

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
runtimeAgent: gajae-code
agentHome: /Users/me/.gjc/agent
handoffRoot: /Users/me/.handoff/sessions
savedAt: 2026-04-26T22:14:31+09:00
progressPercent: 67
worktreeStatus: dirty, 3 changed files
testStatus: passed — pytest tests/payments
nextPromptShort: 결제 webhook 검증부터
autoCommit: skipped
autoCommitSha:
---

## 프로젝트 / 브랜치
...

## 진행 상황
- 진행률: 67% (완료 4 / 전체 6)
- 완료된 작업:
  - ...
- 진행 중인 작업:
  - ...

## 현재 상태 (수정 중 파일 / 미완 작업)
...

## 우선순위 목록
### P0 — webhook 검증 마무리
- 목표: ...
- 관련 파일: `src/payments/webhook.ts`
- 완료 조건: ...
- 다음 프롬프트: ...

## 특이 사항
- 건드리면 안 되는 파일: ...
- 알려진 버그 / 임시 해결책: ...

## 작업 환경 및 이력
- 런타임/에이전트: gajae-code
- 브랜치/HEAD: feat/payments / a1b2c3d
- 마지막 커밋: ...
- 테스트 상태: ...

## 이어갈 프롬프트 (복붙용)
...
```

---

## 환경 변수

| 변수 | 기본값 | 효과 |
|---|---|---|
| `HANDOFF_ROOT` | `~/.handoff/sessions` | handoff 파일 저장/우선 검색 root |
| `HANDOFF_ROOTS` | 없음 | load가 추가로 검색할 root 목록 (`:` 또는 Windows `;` 구분) |
| `HANDOFF_SLUG` | git toplevel basename, 없으면 cwd basename | 프로젝트 slug override |
| `HANDOFF_AGENT` | 자동 감지 | 저장 시 runtime agent override |
| `HANDOFF_TEST_STATUS` | `not recorded` | metadata JSON의 테스트 상태 힌트 |
| `HANDOFF_HOME` | `~/.handoff` | bootstrap clone 위치 |
| `HANDOFF_REPO` | GitHub 원본 | fork/mirror 사용 |
| `HANDOFF_REF` | `main` | branch/tag 고정 |
| `CLAUDE_SKILLS_DIR` | `~/.claude/skills` | Claude skill 링크 위치 |
| `CODEX_SKILLS_DIR` | `~/.codex/skills` | Codex skill 링크 위치 |
| `GAJAE_SKILLS_DIR` | `~/.gjc/agent/skills` | Gajae/GJC skill 링크 위치 |
| `GJC_SKILLS_DIR` | `~/.gjc/agent/skills` | GJC alias skill 링크 위치 |
| `GAJAE_COMMANDS_DIR` | `~/.gjc/agent/commands` | Gajae/GJC direct slash command wrapper 위치 |
| `GJC_COMMANDS_DIR` | `~/.gjc/agent/commands` | GJC alias command wrapper 위치 |
| `OMX_SKILLS_DIR` | `~/.omx/skills` | OMX skill 링크 위치 |
| `WCC_SKILLS_DIR` | `~/.wcc/skills` | WCC/Whale/DeepSeek skill 링크 위치 |
| `CLAUDE_SETTINGS`, `GAJAE_SETTINGS`, `GJC_SETTINGS`, `OMX_SETTINGS`, `WCC_SETTINGS` | 각 agent settings.json (`GAJAE`/`GJC` 기본값은 `~/.gjc/agent/settings.json`) | hook 등록 위치 override |

---

## 개발 워크플로우

별도 build/package step은 없다. 이 레포가 각 agent skill dir로 symlink되므로 `SKILL.md`나 script를 수정하면 즉시 반영된다.

```bash
# metadata smoke test
bash skills/handoff-save/scripts/collect_meta.sh

# redaction smoke test
printf 'TEST_API_KEY=sk-abcdefghijklmnopqrstuvwx\n' | python3 skills/handoff-save/scripts/redact.py

# candidate listing smoke test
python3 skills/handoff-load/scripts/find_candidates.py

# hook dry-run; 현재 cwd slug에 fresh handoff가 있으면 JSON 출력
echo '{}' | bash skills/handoff-load/scripts/load_hook.sh

# installer smoke test with temp dirs
mkdir -p /tmp/handoff-claude/skills /tmp/handoff-gajae/skills
CLAUDE_SKILLS_DIR=/tmp/handoff-claude/skills \
GAJAE_SKILLS_DIR=/tmp/handoff-gajae/skills \
CLAUDE_SETTINGS=/tmp/handoff-claude/settings.json \
GAJAE_SETTINGS=/tmp/handoff-gajae/settings.json \
./install.sh --hook
```

---

## 라이선스

MIT — [LICENSE](LICENSE) 참고.

설계·구현: [@NewTurn2017](https://github.com/NewTurn2017). Anthropic Claude Code Skills 포맷 기반.
