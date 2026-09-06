---
id: openclaw-onboard
title: OpenClaw 온보드
sidebar_position: 8
---

# OpenClaw 온보드 가이드

OpenClaw 게이트웨이, iMessage 채널, 보안 강화 설정을 포함한 전체 셋업 가이드.

## 사전 요구사항

- Podman에서 `openclaw` 컨테이너 빌드 완료
- 호스트에 Ollama 설치 및 서빙 중
- Headscale + Tailscale VPN 구성 완료

## 1. 게이트웨이 설정

### 설정 파일 vs 온보드 위저드

`openclaw onboard` 위저드는 단일 파일로 바인드 마운트된 설정 파일에 **쓸 수 없다**. Podman 제한사항으로 `rename()` 시스템 콜이 바인드 마운트된 단일 파일에서 실패한다.

**반드시 호스트에서 `config/openclaw.json`을 직접 편집**한 후 재시작:

```bash
# 호스트에서 설정 편집
vim config/openclaw.json

# 재시작 (재생성 아님) — 세션 유지
podman restart openclaw
```

### 권장 설정

```json
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "tailnet",
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    },
    "tailscale": {
      "mode": "serve",
      "resetOnExit": true
    }
  }
}
```

| 키 | 값 | 설명 |
|-----|-------|------|
| `mode` | `local` | 이 머신에서 게이트웨이 실행 |
| `bind` | `tailnet` | Tailscale IP에만 바인딩 (VPN 격리) |
| `auth.mode` | `token` | 토큰 기반 인증 |
| `tailscale.mode` | `serve` | Tailnet 내부에만 노출 (Funnel 아님) |
| `tailscale.resetOnExit` | `true` | 종료 시 serve 설정 정리 |

### 환경변수

모든 민감정보는 `.env`에 관리 (커밋 금지). `.env.example` 참고:

```bash
OPENCLAW_GATEWAY_TOKEN=<토큰>
OLLAMA_HOST=http://host.containers.internal:11434
IMSG_SSH_USER=<macOS-사용자명>
```

## 2. iMessage 채널 설정

### 아키텍처

컨테이너에서 macOS `imsg`를 직접 실행할 수 없다. SSH 브릿지로 호스트에 연결:

```
컨테이너              호스트 (macOS)
[openclaw] → SSH → [imsg-guard] → /opt/homebrew/bin/imsg
               ↑          ↑
          host-access   forced command
          네트워크      (imsg만 허용)
```

### Step 1: SSH 키 생성

```bash
mkdir -p ~/.openclaw/keys
ssh-keygen -t ed25519 -f ~/.openclaw/keys/openclaw_imsg -N "" -C "openclaw-imsg"
```

### Step 2: Forced Command로 공개키 등록

`~/.ssh/authorized_keys`에 **한 줄**로 추가:

```
command="/path/to/agent-infrastructure/scripts/imsg-guard",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 <공개키> openclaw-imsg
```

보안 제한:
- `command="...imsg-guard"` — imsg 명령만 허용
- `no-port-forwarding` — 터널링 차단
- `no-agent-forwarding` — SSH 에이전트 전달 차단
- `no-pty` — 셸 접속 차단

### Step 3: Docker Compose 볼륨

`docker-compose.yml`의 openclaw 서비스에 추가:

```yaml
volumes:
  - ~/.openclaw/keys/openclaw_imsg:/home/node/.ssh/openclaw_imsg:ro
  - ./scripts/imsg-host:/usr/local/bin/imsg:ro

networks:
  - openclaw-internal   # egress-proxy 통신
  - host-access         # 호스트 SSH 접근

environment:
  - IMSG_SSH_USER=${IMSG_SSH_USER}
```

### Step 4: 설정 파일에서 활성화

```json
{
  "channels": {
    "imessage": {
      "enabled": true,
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist"
    }
  },
  "plugins": {
    "entries": {
      "imessage": {
        "enabled": true
      }
    }
  }
}
```

### Step 5: 검증

```bash
podman restart openclaw
sleep 3

# SSH 브릿지 테스트
podman exec openclaw imsg --version

# Doctor 확인 — "iMessage: ok" 표시되어야 함
podman exec openclaw openclaw doctor
```

## 3. DM 페어링 흐름

### 초기 페어링

최초 설정 시 `pairing` 모드로 디바이스를 승인해야 한다:

1. 설정에서 `dmPolicy`를 `pairing`으로 설정
2. 재시작: `podman restart openclaw`
3. iPhone에서 OpenClaw Apple ID로 iMessage 전송
4. iMessage로 페어링 코드 수신
5. 승인:

```bash
podman exec openclaw openclaw pairing list imessage
podman exec openclaw openclaw pairing approve imessage <코드>
```

### Allowlist로 전환

승인 후, 모르는 사람에게 응답이 가지 않도록 잠금:

1. 설정 편집: `dmPolicy`를 `allowlist`로 변경
2. 재시작: `podman restart openclaw`
3. 승인된 디바이스만 응답 수신. 새 발신자는 무시됨

## 4. 보안 계층

### imsg-guard (Forced Command 래퍼)

`scripts/imsg-guard`는 SSH forced command로 **호스트**에서 실행:

- 셸 메타문자 차단 (`;`, `|`, `&`, `` ` ``, `$`, `()`, `<>`)
- `/opt/homebrew/bin/imsg`로 시작하는 명령만 허용
- 모든 시도를 `~/.openclaw/logs/imsg-audit.log`에 기록

```
2026-02-15T11:20:50Z OK /opt/homebrew/bin/imsg --version
2026-02-15T11:21:02Z REJECTED unauthorized ls /
2026-02-15T11:21:10Z REJECTED metachar /opt/homebrew/bin/imsg; cat /etc/passwd
```

### 네트워크 격리

```
┌──────────────────────────────────┐
│ openclaw-internal (internal)     │
│  [openclaw] ↔ [egress-proxy]    │
└──────────────────────────────────┘
┌──────────────────────────────────┐
│ host-access                      │
│  [openclaw] → SSH → 호스트 (imsg) │
└──────────────────────────────────┘
```

- `openclaw-internal`: `internal: true` — 외부 접근 불가, egress-proxy만 통신
- `host-access`: iMessage용 호스트 SSH 브릿지

### 바인드 마운트 읽기 전용

```yaml
- ./config/openclaw.json:/home/node/.openclaw/openclaw.json:ro
```

설정 파일은 컨테이너 안에서 읽기 전용. 모든 설정 변경은 호스트에서 수행.

## 5. 운영 원칙

### 해야 할 것

- 호스트에서 설정 편집 후 `podman restart openclaw`
- 읽기 전용 명령은 `podman exec` 사용 (`config get`, `doctor`, `pairing list`)
- 감사 로그 확인: `cat ~/.openclaw/logs/imsg-audit.log`

### 하지 말 것

- `podman compose run --rm`으로 상태 변경 명령 실행 — 세션 데이터 초기화 위험
- 운영 환경에서 설정 바인드 마운트의 `:ro` 제거
- 커밋 파일에 사용자명, 토큰, IP 하드코딩 — `${ENV_VAR}` 사용

### 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| `EBUSY: resource busy or locked` | 단일 파일 바인드 마운트 + 쓰기 시도 | 호스트에서 설정 편집, 컨테이너 안에서 수정 금지 |
| `imsg not found` | 브릿지 스크립트 마운트 경로 오류 | `/usr/local/bin/imsg`로 마운트 |
| `Network is unreachable` (SSH) | `host-access` 네트워크 누락 | compose에 `host-access` 네트워크 추가 |
| `Permission denied` (SSH) | authorized_keys에 키 누락 또는 잘림 | 전체 키 라인 확인 |
| 재시작 후 세션 유실 | `podman compose run --rm` 사용 | `podman restart` 사용 |
| 모르는 사람에게 페어링 코드 전송 | `dmPolicy`가 `pairing` | 승인 후 `allowlist`로 전환 |
