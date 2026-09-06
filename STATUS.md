# OpenClaw Private - 프로젝트 진행 상황

> 최종 업데이트: 2026-03-14
> 버전: 0.1.0 (초기 단계)

## 프로젝트 개요

폐쇄망 전용 프라이빗 AI 어시스턴트 인프라. 외부 클라우드 의존 없이 로컬 하드웨어에서 전체 AI 시스템 스택을 운영한다.

### 핵심 원칙

- 외부 클라우드 의존 제로
- 지정된 디바이스만 통신 가능
- WireGuard VPN을 통한 E2E 암호화
- 로컬 LLM으로 데이터 유출 방지
- 컨테이너 격리로 호스트 보호

## 전체 완성도: ~80%

## 구성요소별 상태

### 완료

| 구성요소 | 위치 | 설명 |
|---------|------|------|
| Headscale (VPN 코디네이터) | `infra/headscale/` | Podman Compose, ACL, DERP relay 설정 완비 |
| Tailscale 클라이언트 | `infra/tailscale/` | macOS/Linux 자동 감지 설치 스크립트 |
| Ollama (로컬 LLM) | `infra/ollama/` | Podman 또는 호스트 설치, 모델 다운로드 스크립트 |
| Model Router 플러그인 | `plugins/model-router/` | TypeScript, 한/영 키워드 기반 태스크 분류 및 모델 라우팅 |
| 운영 스크립트 | `scripts/` | setup-all.sh, health-check.sh, monitor.sh, backup.sh |
| 설정 파일 | `config/` | openclaw.json 모델 프로필 설정 |
| 문서 사이트 | `website/` | Docusaurus 3.9.2, 12개 가이드, 한/영 i18n |

### 미완료 / 부분 구현

| 구성요소 | 상태 | 설명 |
|---------|------|------|
| OpenClaw 앱 본체 | 부분 구현 | 컨테이너 인프라 구축 완료 (`infra/openclaw/`), pnpm 패키지 의존성으로 전환 |
| 테스트 코드 | 부분 구현 | Model Router 테스트 완료 (44건), 추가 컴포넌트 테스트 필요 |
| GPU 가속 | 완료 | `docker-compose.gpu.yml` override 파일로 토글 가능 |
| 70B 모델 지원 | 미지원 확정 | 하드웨어 RAM 36GB < 최소 40GB 요구량, 지원 불가 |
| 클라우드 백업 | 미구현 | 로컬 백업만 구현, S3 등 미연동 |
| 자동 업데이트 | 미구현 | 수동 업데이트만 가능 |

## 기술 스택

| 분류 | 기술 |
|------|------|
| 인프라 | Podman (데몬리스 컨테이너), WireGuard VPN (Headscale + Tailscale) |
| AI/ML | Ollama (모델 목록은 `infra/ollama/models.sh` 참고) |
| 플러그인 | TypeScript 5.0+, strict mode |
| 패키지 매니저 | pnpm 9+ (워크스페이스, 하드링크 기반) |
| 런타임 | Node.js 22+ |
| 문서 | Docusaurus 3.9.2, Markdown, i18n (EN/KO) |
| DB | SQLite3 (Headscale용) |

## 보안 아키텍처 (3계층)

1. **네트워크**: WireGuard VPN — ChaCha20 암호화, Curve25519 키 교환
2. **컨테이너**: Podman (rootless) — `--cap-drop ALL`, `no-new-privileges`
3. **데이터**: 모든 추론 로컬 처리, 외부 전송 없음

## 대상 하드웨어

- 메인 서버: Apple M3 Pro MacBook, 36GB RAM
- 최소 요구: 16GB RAM
- 34B 모델 운영: 36GB+ RAM
- 전체 모델 저장: ~80GB+ 스토리지

## 디렉토리 구조

```
agent-infrastructure/
├── config/                 # OpenClaw 설정 (openclaw.json)
├── infra/                  # 인프라 배포
│   ├── headscale/          # VPN 코디네이터 (Podman)
│   ├── ollama/             # 로컬 LLM 서버 (Podman)
│   └── tailscale/          # VPN 클라이언트 설치
├── plugins/                # 커스텀 확장
│   └── model-router/      # 태스크 기반 모델 라우팅 (TypeScript)
├── scripts/                # 운영 자동화
│   ├── setup-all.sh        # 전체 설치
│   ├── health-check.sh     # 헬스 체크
│   ├── monitor.sh          # 실시간 모니터링
│   └── backup.sh           # 백업 (7개 보관)
├── website/                # Docusaurus 문서 사이트
├── CLAUDE.md               # Claude Code 세션 컨텍스트
├── STATUS.md               # 이 파일
└── README.md               # 프로젝트 개요
```

## Git 이력

| 커밋 | 설명 | 날짜 |
|------|------|------|
| 4a298c1 | Docusaurus 문서 사이트 + i18n | 2026-02-10 |
| c2b6900 | 프라이빗 AI 시스템 아키텍처 문서 | 2026-02-09 |

## 다음 단계 (TODO)

- [x] OpenClaw 컨테이너 격리 환경 구축 (`infra/openclaw/`)
- [x] OpenClaw npm 패키지 의존성으로 전환
- [x] Model Router 플러그인 테스트 코드 작성 (44건 pass)
- [x] NVIDIA GPU 가속 override 파일 분리 (`docker-compose.gpu.yml`)
- [x] 70B 모델 지원 검증 → 36GB RAM < 40GB 최소 요구량, 미지원 확정 (가용 헤드룸: ~24GB)
- [ ] 클라우드 백업 연동 (S3 등)
- [ ] 자동 업데이트 메커니즘 구현
