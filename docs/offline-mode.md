# 오프라인 모드

인터넷 없이 Private AI System 운영하는 방법.

## 오프라인 가능 범위

| 컴포넌트 | 오프라인 | 조건 |
|----------|----------|------|
| Ollama | ✅ 가능 | 모델 사전 다운로드 |
| OpenClaw | ✅ 가능 | 이미지 빌드 완료 |
| Headscale | ⚠️ 부분 | 초기 설정 후 가능 |
| Tailscale | ⚠️ 부분 | P2P 직접 연결 시 |
| telmeet | ✅ 가능 | 로컬 네트워크 내 |

## 사전 준비 (온라인 상태에서)

### 1. Ollama 모델 다운로드

```bash
# 필요한 모델 모두 다운로드
ollama pull qwen2.5-coder:32b
ollama pull deepseek-r1:32b
ollama pull llama3.3:latest

# 다운로드 확인
ollama list
```

### 2. OpenClaw 이미지 빌드

```bash
cd path/to/agent-infrastructure
podman build -t openclaw:local ./infra/openclaw

# 이미지 저장 (백업용)
podman save openclaw:local -o ~/backups/openclaw-local.tar
```

### 3. 의존성 캐시

```bash
# npm 패키지 캐시 (필요시)
cd path/to/agent-infrastructure
pnpm install --offline
```

## 오프라인 실행

### 완전 로컬 모드 (단일 기기)

```bash
# 1. Ollama 시작
ollama serve

# 2. OpenClaw 실행 (네트워크 차단, 컨테이너 이름은 openclaw)
podman run -it --rm --name openclaw \
  --network none \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  -v path/to/agent-infrastructure/config/openclaw.json:/home/node/.openclaw/openclaw.json:ro \
  -v path/to/agent-infrastructure/workspace:/home/node/.openclaw/workspace:rw \
  -e HOME=/home/node \
  openclaw:local \
  bash
```

### 로컬 네트워크 모드 (여러 기기)

Headscale 없이 직접 연결:

```bash
# 기기 A (서버)
ollama serve --host 0.0.0.0

# 기기 B (클라이언트)
export OLLAMA_HOST=http://192.168.1.100:11434
```

### P2P VPN (Tailscale Direct)

이미 연결된 기기 간에는 Headscale 없이도 통신 가능:

```bash
# 기존 연결 확인
tailscale status

# 직접 연결 시 코디네이터 불필요
# (단, 새 기기 추가 불가)
```

## 설정 파일 (오프라인용)

`openclaw.json`:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/qwen2.5-coder:32b",
        "fallbacks": [
          "ollama/llama3.3:latest"
        ]
      }
    }
  },
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "http://localhost:11434/v1"
      }
    }
  },
  "offline": true
}
```

## 제한사항

### 오프라인에서 안 되는 것

| 기능 | 이유 | 대안 |
|------|------|------|
| 모델 다운로드 | 인터넷 필요 | 사전 다운로드 |
| Anthropic API | 클라우드 서비스 | 로컬 LLM 사용 |
| 새 기기 등록 | Headscale 필요 | 사전 등록 |
| 웹 검색 | 인터넷 필요 | 로컬 문서 참조 |

### 성능 고려

- 로컬 LLM은 클라우드보다 느림
- RAM 충분히 확보 필요
- 첫 추론 시 모델 로드 시간 있음

## 긴급 상황 대응

### 인터넷 끊김 시

```bash
# 1. 현재 상태 확인
ollama list
podman images

# 2. 로컬 모드로 전환
# openclaw.json에서 fallback 비활성화

# 3. 오프라인 작업 계속
```

### 복구 후

```bash
# 1. 연결 확인
ping 8.8.8.8

# 2. 모델 업데이트 (선택)
ollama pull qwen2.5-coder:32b

# 3. 정상 모드 복귀
```

## 오프라인 테스트

```bash
#!/bin/bash
# test-offline.sh

# 네트워크 비활성화 (macOS)
# 시스템 환경설정에서 Wi-Fi 끄기

# 테스트
ollama run llama3.3 "Hello, are you working offline?"

# 또는 airplane mode 테스트
networksetup -setairportpower en0 off
# 테스트 후
networksetup -setairportpower en0 on
```

## 체크리스트

- [ ] 필요한 모델 모두 다운로드
- [ ] OpenClaw 이미지 로컬 저장
- [ ] 오프라인 설정 파일 준비
- [ ] 오프라인 테스트 실행
