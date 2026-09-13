# agent-infrastructure

My private OpenClaw setup for closed-circuit networks. Personal use only.

## Overview

Self-hosted AI assistant infrastructure using:

- **Headscale**: Self-hosted Tailscale coordination server
- **Tailscale**: Mesh VPN for secure connectivity
- **Ollama**: Local LLM server
- **OpenClaw**: AI assistant CLI

```
┌─────────────────────────────────────────────────────────────┐
│                     Private Network                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │  macOS   │────│ Headscale│────│  Linux   │              │
│  │ (Client) │    │ (Server) │    │ (Server) │              │
│  └────┬─────┘    └──────────┘    └────┬─────┘              │
│       │                               │                     │
│       └───────────┬───────────────────┘                     │
│                   │                                         │
│            ┌──────▼──────┐                                  │
│            │   Ollama    │                                  │
│            │ (Local LLM) │                                  │
│            └──────┬──────┘                                  │
│                   │                                         │
│            ┌──────▼──────┐                                  │
│            │  OpenClaw   │                                  │
│            └─────────────┘                                  │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# Clone and setup
git clone https://github.com/<username>/agent-infrastructure.git
cd agent-infrastructure

# This repo expects the OpenClaw source at ./openclaw
# (e.g., git submodule or a checked-out sibling directory).
# Example:
#   git submodule add https://github.com/openclaw/openclaw.git openclaw

# Create your local env (do not commit .env)
cp .env.example .env

# Run complete setup
pnpm setup
# or
bash scripts/setup-all.sh
```

## Project Structure

```
agent-infrastructure/
├── config/                 # OpenClaw configuration
│   └── openclaw.json
├── infra/                  # Infrastructure setup
│   ├── headscale/          # Coordination server
│   ├── egress-proxy/       # Squid proxy for egress audit logs
│   ├── tailscale/          # Mesh network client
│   └── ollama/             # Local LLM server
├── scripts/                # Operational scripts
│   ├── setup-all.sh        # Complete setup
│   ├── backup.sh           # Backup routine
│   ├── monitor.sh          # System monitoring
│   ├── health-check.sh     # Health checks
│   ├── route-via-exit-node.sh
│   ├── audit-egress.sh
│   └── setup-audit-cron.sh
├── plugins/                # Custom plugins
│   └── model-router/       # Multi-LLM routing
└── docs/                   # Architecture documentation
```

## 자율형 에이전트

자율형 에이전트 진입점은 별도 프로젝트 raven 의 텔레그램 게이트웨이다. 이 리포에서 돌리지 않는다.

이전에는 아이폰이 ntfy 토픽에 작업을 보내면 워처가 받아 프로젝트 디렉터리에서 ralph 를 실행하는 구조였다. 같은 일을 raven 이 자체 채널로 처리하므로 진입점을 하나로 모았다.

### ralph 경로는 폐기됐다

아래는 유지보수 대상이 아니다. 참고용으로 남겨둘 뿐이다.

| 대상 | 비고 |
|---|---|
| `scripts/ralph-*.sh` | 워처와 프로젝트 생성 |
| `infra/ralph/` | 실행 이미지와 진입 스크립트 |
| `pnpm ralph:*` | 위 스크립트를 부르는 항목 |

실행하면 폐기 안내를 표준 오류로 출력한다. 동작 자체는 막지 않는다.

### ntfy 는 계속 쓴다

알림 수신 용도로 남아 있고 상시 가동 리눅스에서 돈다. 배포는 `pnpm ntfy:ubuntu:deploy` 를 쓴다.

`pnpm ntfy:up` 과 `ntfy:down` 은 맥북 로컬에서 띄우던 예전 방식이다. 리눅스로 옮긴 뒤로는 쓰지 않는다.

## Ollama

Ollama를 호스트에 직접 설치하거나 컨테이너로 띄울 수 있다.

```bash
# 호스트 Ollama 사용 (기본)
# .env에 OLLAMA_HOST=http://host.containers.internal:11434
podman compose up

# 컨테이너 Ollama 사용
# .env에 OLLAMA_HOST=http://ollama:11434
podman compose --profile with-ollama up
```

사용할 모델은 `infra/ollama/models.sh`에서, 라우팅 설정은 `config/openclaw.json`에서 관리한다.

## Secure Egress + Audit

기본 compose는 다음 보안 설정을 적용한다.

- 서비스 포트 localhost 바인딩 (`127.0.0.1`)
- `openclaw` outbound 프록시 변수 주입 (`egress-proxy:3128`)
- 프록시 접근 로그 저장 (`logs/egress-proxy/access.log`)
- Headscale ACL 정책 파일 로드 (`infra/headscale/acl.json`)

권장 운영 순서:

```bash
# 1) Tailnet exit node로 인터넷 경로 고정
pnpm route:exit-node <exit-node-ip-or-hostname>

# 2) egress 로그 요약 리포트 생성 (수동 1회)
pnpm audit:egress

# 3) 15분 주기 자동 감사 등록
pnpm audit:cron
```

감사 리포트 경로:

- 최신 리포트: `logs/audit/latest.md`
- 시점별 리포트: `logs/audit/egress-audit-*.md`

전부 감사(네트워크 레벨)를 위해서는 Exit Node에서 아래를 추가 적용:

```bash
# Exit Node (Linux)에서 실행
sudo bash infra/tailscale/enable-exit-node-audit.sh
sudo bash infra/tailscale/exit-node-audit-report.sh
```

참고: 애플리케이션에 따라 `HTTP_PROXY`/`HTTPS_PROXY`를 무시할 수 있으므로,
"강제 감사" 기준은 Exit Node 네트워크 로그를 사용해야 한다.

## Scripts

```bash
# Health check
pnpm health

# Monitor services
pnpm monitor

# Backup configuration
pnpm backup

# Route traffic via exit node
pnpm route:exit-node <exit-node-ip-or-hostname>

# Generate egress audit report
pnpm audit:egress

# Install cron for periodic audit
pnpm audit:cron
```

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Multi-LLM Strategy](docs/multi-llm-strategy.md)
- [Backup & Recovery](docs/backup-recovery.md)
- [Monitoring](docs/monitoring.md)
- [Offline Mode](docs/offline-mode.md)
- [Mobile Support](docs/mobile-support.md)
- [Update Policy](docs/update-policy.md)
- [TODO](docs/TODO.md)

## Requirements

- Node.js 22+
- pnpm 9+
- Podman (for containers)
- macOS / Linux

## License

GPL-3.0
