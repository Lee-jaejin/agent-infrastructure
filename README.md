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
