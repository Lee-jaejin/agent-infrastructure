# 업데이트 정책

Private AI System 컴포넌트별 버전 관리 및 업데이트 절차.

## 컴포넌트별 업데이트 주기

| 컴포넌트 | 권장 주기 | 자동화 | 중요도 |
|----------|----------|--------|--------|
| Headscale | 월간 | 수동 | 높음 |
| Tailscale 클라이언트 | 자동 | 자동 | 중간 |
| Ollama | 월간 | 수동 | 중간 |
| Ollama 모델 | 필요시 | 수동 | 낮음 |
| OpenClaw 이미지 | 필요시 | 수동 | 중간 |
| macOS/시스템 | 분기 | 수동 | 높음 |

## 업데이트 절차

### Headscale

```bash
# 1. 현재 버전 확인
headscale version

# 2. 백업 먼저
sudo cp /var/lib/headscale/db.sqlite ~/backups/headscale-$(date +%Y%m%d).db

# 3. 업데이트 (패키지 매니저에 따라)
# Debian/Ubuntu
sudo apt update && sudo apt upgrade headscale

# 또는 바이너리 직접
wget https://github.com/juanfont/headscale/releases/latest/download/headscale_linux_amd64
sudo mv headscale_linux_amd64 /usr/local/bin/headscale
sudo chmod +x /usr/local/bin/headscale

# 4. 서비스 재시작
sudo systemctl restart headscale

# 5. 상태 확인
headscale version
sudo systemctl status headscale
```

### Tailscale 클라이언트

```bash
# macOS (자동 업데이트 활성화됨)
# 수동 업데이트:
brew upgrade tailscale

# 또는 앱스토어 버전은 자동
```

### Ollama

```bash
# 1. 현재 버전
ollama --version

# 2. 실행 중인 모델 확인
curl -s http://localhost:11434/api/ps

# 3. 업데이트
brew upgrade ollama

# 4. 서비스 재시작
brew services restart ollama

# 5. 확인
ollama --version
```

### Ollama 모델

```bash
# 새 버전 확인 (수동)
# https://ollama.com/library 에서 확인

# 모델 업데이트 (같은 이름으로 pull하면 최신 버전)
ollama pull qwen2.5-coder:32b
ollama pull deepseek-r1:32b

# 이전 버전 정리
ollama list
ollama rm <old-model>
```

### OpenClaw 컨테이너 이미지

```bash
# 1. 소스 업데이트
cd path/to/agent-infrastructure
git pull origin main

# 2. 이미지 재빌드 (context는 docker-compose와 동일하게)
podman build -t openclaw:local ./infra/openclaw

# 3. 이전 이미지 정리
podman image prune
```

## 롤백 절차

### Headscale 롤백

```bash
# 1. 서비스 중지
sudo systemctl stop headscale

# 2. 이전 바이너리 복원 (백업해둔 경우)
sudo cp ~/backups/headscale-prev /usr/local/bin/headscale

# 3. DB 복원 (필요시)
sudo cp ~/backups/headscale-YYYYMMDD.db /var/lib/headscale/db.sqlite

# 4. 서비스 시작
sudo systemctl start headscale
```

### Ollama 모델 롤백

```bash
# 특정 버전 지정 (있는 경우)
ollama pull qwen2.5-coder:32b-v1.0

# 없으면 이전 버전 재다운로드 불가 - 백업 필요
```

### OpenClaw 롤백

```bash
# 이전 커밋으로 복원
cd path/to/agent-infrastructure
git checkout <previous-commit>
podman build -t openclaw:local ./infra/openclaw
```

## 버전 추적

### 버전 기록 파일

프로젝트 `docs/` 또는 홈 디렉터리 등 원하는 위치에 버전 기록 파일을 둡니다. 예:

```markdown
# Private AI System Versions

| 날짜 | 컴포넌트 | 이전 | 이후 | 비고 |
|------|----------|------|------|------|
| 2026-02-07 | Ollama | 0.5.1 | 0.5.2 | 버그 수정 |
| 2026-02-07 | Headscale | 0.23.0 | 0.24.0 | 보안 패치 |
```

### 버전 확인 스크립트

```bash
#!/bin/bash
# check-versions.sh

echo "=== Private AI System Versions ==="
echo "날짜: $(date)"
echo ""

echo "Headscale: $(headscale version 2>/dev/null || echo 'N/A')"
echo "Tailscale: $(tailscale version 2>/dev/null | head -1 || echo 'N/A')"
echo "Ollama: $(ollama --version 2>/dev/null || echo 'N/A')"
echo "Podman: $(podman --version 2>/dev/null || echo 'N/A')"
echo ""

echo "Ollama 모델:"
ollama list 2>/dev/null || echo "N/A"
```

## 업데이트 전 체크리스트

- [ ] 백업 완료 확인
- [ ] 현재 버전 기록
- [ ] 변경 로그 확인 (breaking changes)
- [ ] 테스트 환경에서 먼저 테스트 (가능한 경우)
- [ ] 롤백 계획 준비

## 자동화 (선택)

### 버전 체크 알림 (온라인 전제)

**주의:** 아래 스크립트는 GitHub API를 호출하므로 **인터넷이 필요한 환경**에서만 사용하세요. 폐쇄망/오프라인 원칙이 있는 배포에서는 사용하지 않거나, 내부 버전 서버로 대체하세요.

```bash
#!/bin/bash
# notify-updates.sh (온라인에서만 사용)

# Ollama 최신 버전 확인 (GitHub API)
LATEST=$(curl -s https://api.github.com/repos/ollama/ollama/releases/latest | jq -r '.tag_name')
CURRENT=$(ollama --version | awk '{print $2}')

if [ "$LATEST" != "$CURRENT" ]; then
  osascript -e "display notification \"Ollama $LATEST 사용 가능 (현재: $CURRENT)\" with title \"업데이트 알림\""
fi
```

## 체크리스트

- [ ] check-versions.sh 배포
- [ ] 버전 기록 파일 생성
- [ ] 업데이트 알림 스크립트 설정
- [ ] 롤백 테스트 실행
