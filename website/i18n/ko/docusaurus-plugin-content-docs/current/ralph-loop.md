---
id: ralph-loop
title: Ralph Loop
sidebar_position: 9
---

# Ralph Loop

Claude Code 구독과 Podman 격리 기반의 장시간 자율 에이전트 루프.

[PageAI-Pro/ralph-loop](https://github.com/PageAI-Pro/ralph-loop)를 포크해서 Docker sandbox를 rootless Podman으로 교체하고, model-router 플러그인을 연동해 모델을 자동 선택합니다.

## 동작 방식

매 이터레이션마다 Ralph는:

1. `.agent/tasks.json`에서 우선순위가 가장 높은 미완료 태스크를 읽음
2. model-router로 태스크를 분류 → `claude-sonnet-4-6` 또는 `claude-opus-4-6` 선택
3. Podman 컨테이너 안에서 `claude --dangerously-skip-permissions` 실행
4. 완료 / 차단 / 결정 신호를 모니터링
5. 이터레이션 히스토리를 저장하고 루프 반복

```
./ralph.sh -n 20
  └── 이터레이션 1
        ├── select-model → claude-sonnet-4-6  (코딩 태스크)
        ├── podman run ralph-claude -- claude --model claude-sonnet-4-6
        └── ✓ 태스크 커밋
  └── 이터레이션 2
        ├── select-model → claude-opus-4-6  (아키텍처 분석 태스크)
        ├── podman run ralph-claude -- claude --model claude-opus-4-6
        └── ✓ 태스크 커밋
  └── 🎉 모든 태스크 완료
```

## 모델 선택

model-router 플러그인이 현재 태스크 설명을 기반으로 자동으로 모델을 선택합니다:

| 태스크 유형 | 모델 | 조건 |
|------------|------|------|
| `coding` | `claude-sonnet-4-6` | code, bug, implement, test, build… |
| `reasoning` | `claude-opus-4-6` | analyze, compare, architecture, strategy… |
| `general` | `claude-sonnet-4-6` | 그 외 모든 요청 |

## 설정

### 1. Podman 이미지 빌드 (최초 1회)

```bash
pnpm ralph:build
```

Node.js 22와 Claude Code CLI가 포함된 rootless Podman 이미지를 빌드합니다.

### 2. claude.ai 구독으로 로그인 (최초 1회)

```bash
pnpm ralph:login
```

컨테이너 안에서 대화형 로그인을 실행하고, 인증 정보를 `~/.claude/`에 저장합니다.

### 3. 태스크 목록 작성

프로젝트에 `.agent/tasks.json` 생성:

```json
[
  {
    "id": "TASK-001",
    "title": "회원가입 폼에 입력값 검증 추가",
    "description": "이메일과 비밀번호 필드에 입력값 검증을 구현하고 테스트",
    "priority": 1,
    "status": "pending"
  },
  {
    "id": "TASK-002",
    "title": "현재 인증 아키텍처 분석",
    "description": "현재 인증 전략과 트레이드오프를 분석하고 문서화",
    "priority": 2,
    "status": "pending"
  }
]
```

선택적으로 `.agent/PROMPT.md`에 프로젝트 컨텍스트를 작성합니다 ([프롬프트 레이어](#프롬프트-레이어) 참조).

### 4. 실행

```bash
# 프로젝트 디렉토리를 지정해 실행
pnpm ralph -- --project-dir=/path/to/your/project -n 20

# 직접 실행
bash infra/ralph/ralph.sh --project-dir=/path/to/your/project -n 20
```

## 프롬프트 레이어

Ralph는 런타임에 세 개의 독립적인 레이어를 합쳐 프롬프트를 구성합니다:

| 레이어 | 소스 | 내용 |
|--------|------|------|
| **1. 프레임워크** | `infra/ralph/.agent/PROMPT.md` | 태스크 루프 규칙, COMPLETE/BLOCKED/DECIDE 신호 정의 |
| **2. 프로젝트** | `PROJECT_DIR/.agent/PROMPT.md` | 기술 스택, 컨벤션, 도메인 제약, 완료 기준 |
| **3. 행동 원칙** | `AGENT_GUIDE_PATH/principles/` | 코딩 원칙 (먼저 생각하기, 단순함 우선…) |

레이어 1은 항상 포함됩니다. 레이어 2·3은 선택 사항 — 파일이 없으면 자동으로 건너뜁니다.

### 프로젝트 프롬프트 (레이어 2)

예시 템플릿을 복사해서 작성합니다:

```bash
cp infra/ralph/.agent/PROMPT.project.example.md /path/to/your/project/.agent/PROMPT.md
```

태스크 루프 규칙(레이어 1)이나 행동 원칙(레이어 3)은 반복하지 않습니다. 프로젝트 고유의 컨텍스트만 작성합니다:

```markdown
## Overview
Next.js 14 기반 SaaS 앱. Stripe 결제, Prisma, PostgreSQL.

## Tech Stack
- TypeScript strict, pnpm, Vitest + Playwright

## Conventions
- Server Component 우선, 상태 필요 시만 'use client'
- DB 접근은 Prisma만, raw SQL 금지
- Conventional Commits

## Constraints
- 시크릿 하드코딩 금지 — .env 사용
- pnpm test 통과 후 커밋
```

### 행동 원칙 (레이어 3)

`.env`에 로컬 [agent-guide](https://github.com/PageAI-Pro/agent-guide) 경로를 설정합니다:

```bash
AGENT_GUIDE_PATH=/Users/yourname/Study/ai/agent-guide
```

Ralph가 매 실행 시 `$AGENT_GUIDE_PATH/principles/README.md`를 읽으므로, agent-guide를 수정하면 다음 실행부터 자동 반영됩니다.

## 신호(Signals)

Ralph는 Claude 출력에서 특수 태그를 감지해 루프를 제어합니다:

| 신호 | 태그 | 동작 |
|------|------|------|
| 전체 완료 | `<COMPLETE>…</COMPLETE>` | 성공으로 종료 |
| 사람 입력 필요 | `<BLOCKED>…</BLOCKED>` | 일시 정지 후 알림 |
| 결정 필요 | `<DECIDE>…</DECIDE>` | 일시 정지 후 알림 |

## 컨테이너 격리

Podman 컨테이너는 최소 권한으로 실행됩니다:

```
--security-opt no-new-privileges:true
--cap-drop ALL
--userns=keep-id
```

| 마운트 | 모드 | 목적 |
|--------|------|------|
| `PROJECT_DIR` → `/workspace` | `rw` | Claude가 프로젝트 파일 읽기/쓰기 |
| `~/.claude` → `/root/.claude` | `ro` | 인증 토큰 (읽기 전용, 에이전트가 수정 불가) |

## 파일 구조

```
infra/ralph/
├── Containerfile                    # Podman 이미지 정의
├── ralph.sh                         # 메인 루프 스크립트
├── projects.json                    # 멀티 프로젝트 레지스트리 (alias → 경로)
├── scripts/
│   ├── lib/                         # 로깅, 스피너, 타이밍 헬퍼
│   └── select-model.mjs             # tasks.json → model-router → 모델명 출력
└── .agent/
    ├── PROMPT.md                    # 레이어 1: 프레임워크 프롬프트 (태스크 루프, 신호)
    ├── PROMPT.project.example.md    # 레이어 2 템플릿: 프로젝트에 복사해서 사용
    └── tasks.json                   # 태스크 목록 예시

scripts/
├── ralph-imsg-watch.sh              # ntfy 답장 수신 → Ralph 재개
├── ralph-task-watch.sh              # ntfy 태스크 수신 → Ralph 시작
├── ralph-start-projects.sh         # 전체 프로젝트 watch 일괄 시작
├── ralph-new-project.sh            # 신규 프로젝트 스캐폴딩 + GitHub 연동 + projects.json 등록
└── ralph-new-project-watch.sh      # ntfy 신규 프로젝트 요청 수신 → ralph-new-project.sh 호출
```

## 아이폰에서 신규 프로젝트 개설

ntfy에 메시지 한 줄만 보내면 — 프로젝트 디렉토리 생성, git 초기화, GitHub 레포 생성, Ralph 등록까지 한 번에 완료됩니다.

### 사전 조건

| 조건 | 설정 방법 |
|------|---------|
| `RALPH_PROJECTS_BASE_DIR` (필수) | 신규 프로젝트가 생성될 기본 디렉토리 |
| `gh` CLI 인증 (선택) | GitHub 레포 자동 생성 — `gh auth login` 한 번만 |
| `GITHUB_OWNER` (선택) | GitHub 사용자명 또는 조직명 |

```bash
# .env
RALPH_PROJECTS_BASE_DIR=/Users/yourname/projects
GITHUB_OWNER=your-github-username        # 생략 시 GitHub 단계 건너뜀
NTFY_RALPH_NEW_PROJECT_TOPIC=ralph-new-project  # 기본값, 생략 가능
```

### iPhone에서 메시지 전송

iPhone Safari → `http://100.64.0.1:8095` → 토픽 `ralph-new-project`

| 메시지 형식 | 예시 |
|------------|------|
| 프로젝트명만 | `my-webapp` |
| 프로젝트명 + 설명 | `my-webapp: Next.js 이커머스 프론트엔드` |

### 실행 흐름

```
iPhone → "my-webapp: Next.js 이커머스 프론트엔드"
  → ralph:new-project-watch 감지
  → /projects/my-webapp/ 생성
      .agent/tasks.json     (빈 태스크 목록)
      .agent/PROMPT.md      (템플릿 — 프로젝트 컨텍스트 직접 작성)
      README.md
      .gitignore
  → git init && 초기 커밋
  → gh repo create your-github-username/my-webapp --private --push  (GITHUB_OWNER 설정 시)
  → infra/ralph/projects.json에 "my-webapp" 등록
  → ralph:task-watch[my-webapp] 자동 시작
  → "[my-webapp] 프로젝트 생성 완료" → ntfy ralph 토픽으로 알림 전송
```

알림이 도착하는 즉시 `ralph-task-my-webapp` 토픽으로 태스크를 보낼 수 있습니다 — watcher가 이미 실행 중입니다.

### watcher 시작

`RALPH_PROJECTS_BASE_DIR`이 설정된 경우 `yarn ralph:start-projects` 실행 시 자동으로 포함됩니다. 단독 실행:

```bash
yarn ralph:new-project-watch
```

> **새 프로젝트 추가 시 재시작 불필요.** `ralph-new-project-watch`가 프로젝트를 생성할 때 해당 프로젝트의 `ralph:task-watch`를 자동으로 시작합니다. `ralph:start-projects` 재시작은 머신 재부팅 후나 프로세스가 죽었을 때만 필요합니다.

### 프로젝트 프롬프트 설정

생성 후 `.agent/PROMPT.md`를 편집해 기술 스택과 컨벤션을 입력합니다 ([프롬프트 레이어](#프롬프트-레이어) 레이어 2):

```bash
nano /Users/yourname/projects/my-webapp/.agent/PROMPT.md
```

---

## 멀티 프로젝트 모드

여러 프로젝트를 동시에 독립적으로 실행합니다. 프로젝트별로 별도의 ntfy 토픽을 사용합니다.

### 1. 프로젝트 등록

`infra/ralph/projects.json` 편집:

```json
{
  "webapp": "/Users/yourname/projects/webapp",
  "api": "/Users/yourname/projects/api"
}
```

git이 초기화된 디렉토리면 어디든 등록 가능합니다. `.agent/tasks.json`은 첫 태스크 수신 시 자동 생성됩니다.

### 2. 전체 watch 시작

```bash
yarn ntfy:up
yarn ralph:start-projects   # ralph:watch 1개 + 프로젝트별 ralph:task-watch 시작
```

`ralph:start-projects`가 `projects.json`을 읽고:
- 프로젝트별로 `ralph:task-watch` 1개씩 시작 (각자 `ralph-task-{name}` 토픽 구독)
- 공통 `ralph:watch` 1개 시작 (모든 프로젝트의 BLOCKED/DECIDE 답장 처리)

### 3. iPhone 토픽

| 동작 | ntfy 토픽 |
|------|-----------|
| webapp에 태스크 전송 | `ralph-task-webapp` |
| api에 태스크 전송 | `ralph-task-api` |
| 모든 알림 읽기 | `ralph` |
| BLOCKED/DECIDE 답장 | `ralph-reply` |

여러 프로젝트가 동시에 대기 중일 수 있으므로, 답장 시 프로젝트명 prefix를 붙입니다:
```
webapp: 네, A로 진행하세요
```

---

## iPhone 연동 (ntfy)

Ralph는 DECIDE/BLOCKED/COMPLETE 신호를 ntfy를 통해 iPhone으로 전송하고, 답장을 받으면 루프를 재개합니다. iPhone에서 새 태스크를 전송할 수도 있습니다. OpenClaw(iMessage)와 별도의 채팅 채널로 Ralph와 소통할 수 있습니다.

| 에이전트 | 채널 |
|---------|------|
| OpenClaw | iMessage |
| Ralph | ntfy 웹 UI (iPhone, VPN 경유) |

### 1. `.env` 설정

```bash
# ntfy 서버 (컨트롤 타워에서 실행)
NTFY_URL=http://localhost:8095
NTFY_RALPH_TOPIC=ralph
NTFY_RALPH_REPLY_TOPIC=ralph-reply

# 단일 프로젝트 모드에서만 사용
NTFY_RALPH_TASK_TOPIC=ralph-task
RALPH_PROJECT_DIR=/path/to/your/project

# 행동 원칙 (선택 사항)
AGENT_GUIDE_PATH=/Users/yourname/Study/ai/agent-guide
```

> `NTFY_URL`이 `localhost`인 이유: Ralph와 watch 스크립트는 ntfy와 같은 머신(컨트롤 타워)에서 실행됩니다. iPhone은 VPN을 통해 `http://100.64.0.1:8095`로 접속합니다.

### 2. watch 서비스 시작

**단일 프로젝트:**
```bash
yarn ntfy:up
yarn ralph:watch &
yarn ralph:task-watch &
```

**멀티 프로젝트:**
```bash
yarn ntfy:up
yarn ralph:start-projects
```

### 3. iPhone에 ntfy 설정

사전 조건: iPhone이 headscale VPN에 연결되어 있어야 합니다 — [iPhone VPN 설정](./iphone-vpn-setup.md) 참조.

iPhone Safari에서 `http://100.64.0.1:8095` 접속

| 동작 | 토픽 |
|------|------|
| 알림 읽기 | `ralph` |
| 태스크 전송 (단일) | `ralph-task` |
| 태스크 전송 (멀티) | `ralph-task-{name}` |
| BLOCKED/DECIDE 답장 | `ralph-reply` |

### 4. iPhone에서 태스크 전송

1. iPhone Safari에서 `http://100.64.0.1:8095` 접속 (VPN 연결 필수)
2. 해당 프로젝트의 태스크 토픽 → 태스크 설명을 메시지로 게시
3. `ralph:task-watch`가 감지 → `tasks.json`에 추가 → `yarn ralph` 자동 시작

### 5. BLOCKED/DECIDE 답장

Ralph가 일시 정지하고 입력을 기다릴 때:

1. `http://100.64.0.1:8095` → 토픽 `ralph`에서 질문 확인
   - 알림 제목에 프로젝트명이 표시됩니다: `[webapp] Ralph BLOCKED`
2. 토픽 `ralph-reply`에 답변 게시
   - 단일 프로젝트: 답변 텍스트만
   - 멀티 프로젝트: 프로젝트명 prefix 포함: `webapp: 네, A로 진행하세요`
3. `ralph:watch`가 감지 → Ralph 재개

### 전체 흐름

```
iPhone (ntfy 웹 UI) → "ralph-task-webapp"에 게시
  → ralph:task-watch[webapp] 감지 → tasks.json에 추가 → ralph 시작
  → Ralph 작업 중...
  → Ralph가 BLOCKED/DECIDE 신호 → "[webapp] Ralph BLOCKED"를 "ralph" 토픽에 게시
  → iPhone이 ntfy 웹 UI에서 알림 확인
  → iPhone이 "ralph-reply"에 "webapp: 네 진행하세요" 게시
  → ralph:watch 감지 → HUMAN_REPLY.md 작성 → Ralph 재개
  → Ralph 완료 → "ralph" 토픽에 COMPLETE 게시
```

---

## 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `RALPH_IMAGE` | `ralph-claude` | Podman 이미지 이름 |
| `NTFY_URL` | — | ntfy 서버 URL (예: `http://localhost:8095`) |
| `NTFY_RALPH_TOPIC` | `ralph` | BLOCKED/DECIDE/COMPLETE 알림 발신 토픽 |
| `NTFY_RALPH_REPLY_TOPIC` | `ralph-reply` | 사용자 답장 수신 토픽 |
| `NTFY_RALPH_TASK_TOPIC` | `ralph-task` | 태스크 수신 토픽 (단일 프로젝트 모드) |
| `RALPH_PROJECT_DIR` | — | 프로젝트 경로 (단일 프로젝트 모드) |
| `AGENT_GUIDE_PATH` | — | agent-guide 레포 경로 (레이어 3 행동 원칙) |
| `RALPH_PROJECTS_BASE_DIR` | — | iPhone에서 신규 프로젝트 생성 시 기본 디렉토리 |
| `GITHUB_OWNER` | — | GitHub 사용자/조직명 (`gh auth login` 필요) |
| `NTFY_RALPH_NEW_PROJECT_TOPIC` | `ralph-new-project` | 신규 프로젝트 요청 수신 토픽 |

`.env`에 설정하거나 직접 전달:

```bash
RALPH_IMAGE=my-ralph pnpm ralph -- -n 10
```

## 이터레이션 히스토리

각 이터레이션은 `.agent/history/ITERATION-{SESSION}-{N}.txt`에 저장되어 나중에 검토할 수 있습니다.

## 모니터링

**Ralph 실행 여부 확인:**
```bash
pgrep -la "ralph\.sh"
```

**태스크 상태 확인:**
```bash
cat /path/to/project/.agent/tasks.json | python3 -m json.tool
```
`status`가 `pending` (대기), `completed` (완료), `cancelled` (취소)입니다.

**이터레이션 로그 실시간 추적:**
```bash
ls -t /path/to/project/.agent/history/ | head -3
tail -f /path/to/project/.agent/history/ITERATION-*.txt
```

**iPhone:** ntfy `ralph` 토픽에서 `[프로젝트] Ralph: starting`, `BLOCKED`, `DECIDE`, `COMPLETE` 알림으로 확인합니다.

## 작업 취소 및 되돌리기

**Ralph 즉시 중단:**
```bash
pkill -f "ralph\.sh"
podman stop $(podman ps -q --filter ancestor=ralph-claude 2>/dev/null) 2>/dev/null || true
```

**완료된 커밋 되돌리기** (Ralph는 태스크 완료마다 커밋):
```bash
cd /path/to/project
git log --oneline -10       # Ralph가 한 작업 확인
git reset --soft HEAD~1     # 마지막 커밋 취소 (파일은 유지)
git reset --soft HEAD~3     # 마지막 3개 커밋 취소
git revert HEAD             # 안전한 revert (히스토리 보존, push 후 사용)
```

**대기 중인 태스크 취소** — `.agent/tasks.json`에서 해당 태스크의 `status`를 `"cancelled"`로 변경합니다.

**자연스러운 중단 지점:** Ralph가 `BLOCKED` / `DECIDE` 신호를 내면 자동으로 멈춥니다. ntfy 답장을 보내지 않으면 무기한 대기 상태로 유지됩니다.

## `ralph:start-projects` 상시 유지

터미널을 닫아도 프로세스가 유지되도록 tmux 세션에서 실행합니다:

```bash
# 백그라운드 tmux 세션으로 시작
tmux new-session -d -s ralph 'cd /path/to/agent-infrastructure && yarn ralph:start-projects'

# 로그 확인 (접속)
tmux attach -t ralph

# 로그 보면서 분리: Ctrl+B 후 D
```

머신 재부팅 후 위 명령을 다시 실행합니다 (또는 셸 프로파일 / launchd에 등록).

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `OAuth token has expired` | Claude Code 로그인 만료 | `yarn ralph:login` |
| `all tasks already completed` | `--project-dir` 형식 오류 | `--project-dir=VALUE` 형식 사용 (공백 아닌 `=`) |
| `must be run inside a git repository` | 프로젝트 디렉토리가 git 저장소 아님 | `git init && git commit --allow-empty -m "initial"` |
| `timeout: command not found` | macOS에 GNU `timeout` 없음 | 수정 완료 — `timeout`이 스크립트에서 제거됨 |
| `ralph already running` (오탐) | pgrep이 task-watch 자신을 Ralph로 오인 | 수정 완료 — pgrep이 `ralph\.sh`만 탐지 |
| 태스크 큐에만 있고 Ralph 미시작 | `ralph:start-projects` 죽어있음 | tmux로 재시작; 즉시 실행은 `yarn ralph -- --project-dir=...` |
| `ralph:new-project-watch` 미시작 | `RALPH_PROJECTS_BASE_DIR` 미설정 | `.env`에 추가 |
| GitHub 레포 생성 실패 | 레포 이미 존재하거나 `gh` 미인증 | remote 없이 계속 진행; `git remote add origin ...`으로 수동 연결 |

## OpenClaw와의 관계

Ralph는 OpenClaw와 별개로 동작하는 도구입니다. OpenClaw는 로컬 Ollama 모델로 상시 멀티채널 메시징을 처리하고, Ralph는 Claude Code 구독을 사용해 자율 코딩 세션을 실행합니다. 두 도구는 목적이 다르며 함께 사용할 수 있습니다.
