# 백업/복구 전략

Private AI System의 데이터 보호 및 복구 계획.

## 백업 대상

| 컴포넌트 | 데이터 위치 | 중요도 |
|----------|------------|--------|
| Headscale | `/var/lib/headscale/db.sqlite` | 높음 |
| Headscale 설정 | `/etc/headscale/config.yaml` | 높음 |
| OpenClaw 설정 | `config/openclaw.json` (호스트) | 중간 |
| OpenClaw 데이터·세션 | openclaw-data 볼륨 (컨테이너) | 낮음 |
| OpenClaw 워크스페이스 | `workspace/` (호스트, SOUL.md, AGENTS.md 등) | 중간 |
| Ollama 모델 | `~/.ollama/models/` | 낮음 (재다운로드 가능) |
| Tailscale 키 | `/var/lib/tailscale/` | 높음 |

## 백업 스크립트

이 레포의 `pnpm backup`(scripts/backup.sh)은 **config/** 와 Headscale, Ollama 모델 목록만 백업합니다. **workspace/** 를 백업하려면 아래 예시에 있는 `openclaw-workspace` 복사 단계를 추가하거나, 수동으로 `workspace/` 디렉터리를 복사하세요.

### 전체 백업

```bash
#!/bin/bash
# backup-private-ai.sh

BACKUP_DIR="$HOME/backups/private-ai/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Headscale (서버에서 실행)
cp /var/lib/headscale/db.sqlite "$BACKUP_DIR/headscale.db"
cp /etc/headscale/config.yaml "$BACKUP_DIR/headscale-config.yaml"

# OpenClaw 설정 (이 레포 기준)
cp -r path/to/agent-infrastructure/config "$BACKUP_DIR/openclaw-config"

# OpenClaw 워크스페이스 (SOUL.md, AGENTS.md, USER.md 등)
cp -r path/to/agent-infrastructure/workspace "$BACKUP_DIR/openclaw-workspace" 2>/dev/null || true

# 압축
tar -czf "$BACKUP_DIR.tar.gz" -C "$(dirname $BACKUP_DIR)" "$(basename $BACKUP_DIR)"
rm -rf "$BACKUP_DIR"

echo "백업 완료: $BACKUP_DIR.tar.gz"
```

### 자동 백업 (cron)

```bash
# 매일 새벽 3시 백업
0 3 * * * /path/to/backup-private-ai.sh >> /var/log/backup.log 2>&1
```

## 복구 절차

### Headscale 복구

```bash
# 1. 서비스 중지
sudo systemctl stop headscale

# 2. DB 복원
sudo cp backup/headscale.db /var/lib/headscale/db.sqlite
sudo cp backup/headscale-config.yaml /etc/headscale/config.yaml

# 3. 권한 설정
sudo chown headscale:headscale /var/lib/headscale/db.sqlite

# 4. 서비스 시작
sudo systemctl start headscale
```

### OpenClaw 복구

```bash
# 설정 복원
cp -r backup/openclaw-config/* path/to/agent-infrastructure/config/

# 워크스페이스 복원 (백업에 포함한 경우)
cp -r backup/openclaw-workspace/* path/to/agent-infrastructure/workspace/ 2>/dev/null || true
```

### Ollama 모델 (재다운로드)

```bash
ollama pull qwen2.5-coder:32b
ollama pull deepseek-r1:32b
ollama pull llama3.3:latest
```

## 백업 보관 정책

| 주기 | 보관 기간 | 위치 |
|------|----------|------|
| 일간 | 7일 | 로컬 |
| 주간 | 4주 | 로컬 + 외장 |
| 월간 | 6개월 | 외장 드라이브 |

## 백업 검증

```bash
#!/bin/bash
# verify-backup.sh

BACKUP_FILE=$1

# 압축 해제 테스트
tar -tzf "$BACKUP_FILE" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ 압축 파일 정상"
else
  echo "❌ 압축 파일 손상"
  exit 1
fi

# Headscale DB 무결성
sqlite3 "$BACKUP_FILE/headscale.db" "PRAGMA integrity_check;"
```

## 재해 복구 시나리오

### 시나리오 1: 서버 완전 손실

1. 새 서버 준비
2. Headscale 설치
3. 백업에서 DB + 설정 복원
4. 클라이언트 자동 재연결 (키 유지)

### 시나리오 2: 설정 파일 손상

1. 최신 백업에서 설정 복원
2. 서비스 재시작

### 시나리오 3: Ollama 모델 손실

1. `ollama pull`로 재다운로드
2. 설정은 그대로 유지

## 체크리스트

- [ ] 백업 스크립트 작성
- [ ] cron 설정
- [ ] 외장 드라이브 연결
- [ ] 복구 테스트 실행
- [ ] 백업 알림 설정
