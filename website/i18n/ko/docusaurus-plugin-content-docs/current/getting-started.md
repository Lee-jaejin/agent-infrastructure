---
id: getting-started
title: 시작하기
sidebar_position: 4
---

# 시작하기

Private AI 시스템 빠른 설정 가이드입니다.

## 사전 요구사항

- macOS 또는 Linux
- Podman 및 Podman Compose
- 16GB+ RAM (34B 모델은 36GB 권장)
- Node.js 20+

## 빠른 설정

```bash
# 저장소 클론
git clone https://github.com/jaejin/agent-infrastructure.git
cd agent-infrastructure

# 전체 설정 실행
./scripts/setup-all.sh
```

설정 스크립트가 수행하는 작업:
1. Ollama 설치 및 모델 다운로드
2. Headscale 컨테이너 시작
3. OpenClaw 컨테이너 빌드 및 실행
4. 모델 라우터 설정

## 수동 설정

### 1단계: Ollama

```bash
# Ollama 설치
brew install ollama

# 서비스 시작
ollama serve

# 모델 다운로드
bash infra/ollama/models.sh
```

### 2단계: Headscale

```bash
cd infra/headscale
podman compose up -d
```

### 3단계: OpenClaw

```bash
cd infra/openclaw
podman compose up -d
```

### 4단계: Model Router 플러그인

```bash
cd plugins/model-router
pnpm install
pnpm build
```

## 설치 확인

```bash
# Ollama 확인
curl http://localhost:11434/api/tags

# Headscale 확인
podman logs headscale

# OpenClaw 확인
curl http://localhost:18789/health
```

## 다음 단계

- [Headscale 설정](/ko/headscale-setup) - VPN 코디네이터 설정
- [모바일 지원](/ko/mobile-support) - 모바일 기기 연결
- [Model Router](/ko/model-router) - 모델 라우팅 커스터마이즈
