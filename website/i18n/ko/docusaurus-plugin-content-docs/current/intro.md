---
id: intro
title: 소개
sidebar_position: 1
slug: /
---

# OpenClaw Private

폐쇄형 네트워크를 위한 Private AI 시스템. 개인 사용 전용.

## 개요

이 프로젝트는 완전한 프라이빗 AI 인프라를 제공합니다:

- **외부 클라우드 의존 없음** - 모든 처리가 로컬에서 수행
- **지정된 기기만 통신 가능** - WireGuard VPN으로 보안
- **모든 통신 암호화** - Headscale/Tailscale을 통한 종단 간 암호화
- **로컬 LLM으로 데이터 유출 방지** - Ollama를 사용한 로컬 추론
- **컨테이너 격리로 호스트 보호** - OpenClaw가 격리된 컨테이너에서 실행

## 컴포넌트

| 컴포넌트 | 용도 |
|---------|------|
| **Headscale** | 자체 호스팅 Tailscale 코디네이터 |
| **Tailscale** | WireGuard VPN 클라이언트 |
| **Ollama** | 로컬 LLM 추론 엔진 |
| **OpenClaw** | 컨테이너 내 AI 게이트웨이 |
| **Model Router** | 작업 기반 모델 선택 |

## 모델 전략

작업 유형별 로컬 모델 라우팅 (현재 모델 목록은 `config/openclaw.json` 참고):

| 작업 유형 | 사용 사례 |
|----------|----------|
| **코딩** | 코드 생성, 디버깅 |
| **추론** | 분석, 복잡한 논리 |
| **일반** | 일반 대화 |

## 빠른 시작

```bash
# 저장소 클론
git clone https://github.com/jaejin/agent-infrastructure.git
cd agent-infrastructure

# 설정 실행
./scripts/setup-all.sh
```

자세한 내용은 [시작하기](/ko/getting-started)를 참조하세요.
