#!/bin/bash
# deploy-ntfy-ubuntu.sh — ntfy를 Ubuntu 서버에 배포한다
# Usage: pnpm ntfy:ubuntu:deploy
#
# 사전 조건:
#   - UBUNTU_HOST, UBUNTU_SSH_USER가 .env에 설정되어 있어야 함
#   - Ubuntu 서버에 Docker 또는 podman-compose가 설치되어 있어야 함
#   - SSH 키 인증이 설정되어 있어야 함
#
# 완료 후:
#   - .env의 NTFY_URL을 http://${UBUNTU_HOST}:8095 로 변경
#   - iPhone ntfy 앱 서버 주소도 동일하게 변경

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a && . "${PROJECT_DIR}/.env" && set +a
fi

UBUNTU_HOST="${UBUNTU_HOST:?UBUNTU_HOST이 .env에 설정되어 있지 않습니다}"
UBUNTU_SSH_USER="${UBUNTU_SSH_USER:?UBUNTU_SSH_USER가 .env에 설정되어 있지 않습니다}"
NTFY_PORT="${NTFY_PORT:-8095}"

echo "ntfy 배포 중: ${UBUNTU_SSH_USER}@${UBUNTU_HOST} ..."

# compose 파일 전송
scp -q "${PROJECT_DIR}/infra/ntfy/docker-compose.yml" \
  "${UBUNTU_SSH_USER}@${UBUNTU_HOST}:/tmp/ntfy-compose.yml"

# 원격 실행: ntfy 시작
ssh "${UBUNTU_SSH_USER}@${UBUNTU_HOST}" "
  set -euo pipefail
  mkdir -p ~/ntfy
  cp /tmp/ntfy-compose.yml ~/ntfy/docker-compose.yml
  cd ~/ntfy

  if command -v docker &>/dev/null; then
    docker compose up -d
  elif command -v podman-compose &>/dev/null; then
    podman-compose up -d
  else
    echo 'Error: docker 또는 podman-compose가 필요합니다' >&2
    exit 1
  fi

  sleep 2
  curl -sf http://localhost:${NTFY_PORT}/v1/health >/dev/null && echo 'ntfy 헬스체크: OK'
"

echo ""
echo "배포 완료."
echo ""
echo "=== 다음 단계 ==="
echo ""
echo "1. .env 업데이트:"
echo "   NTFY_URL=http://${UBUNTU_HOST}:${NTFY_PORT}"
echo ""
echo "2. iPhone ntfy 앱 서버 주소 변경:"
echo "   http://${UBUNTU_HOST}:${NTFY_PORT}"
echo ""
echo "3. 기존 macOS ntfy 중지 (선택):"
echo "   pnpm ntfy:down"
