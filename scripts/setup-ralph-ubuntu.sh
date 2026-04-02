#!/bin/bash
# setup-ralph-ubuntu.sh — Ubuntu 서버에 ralph 실행 환경을 준비한다
# Usage: pnpm ralph:ubuntu:setup
#
# 이 스크립트가 하는 것:
#   1. Node.js 22+ 확인
#   2. Docker 또는 Podman 확인
#   3. ralph Containerfile 전송 + 이미지 빌드
#
# 이 스크립트가 하지 않는 것 (수동 필요):
#   - Claude 로그인 (아래 안내 참고)
#   - 프로젝트 디렉토리 동기화 (git clone / rsync)
#
# 사전 조건:
#   - UBUNTU_HOST, UBUNTU_SSH_USER가 .env에 설정되어 있어야 함
#   - Ubuntu 서버에 Node.js 22+, Docker 또는 Podman이 설치되어 있어야 함
#   - SSH 키 인증이 설정되어 있어야 함

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a && . "${PROJECT_DIR}/.env" && set +a
fi

UBUNTU_HOST="${UBUNTU_HOST:?UBUNTU_HOST이 .env에 설정되어 있지 않습니다}"
UBUNTU_SSH_USER="${UBUNTU_SSH_USER:?UBUNTU_SSH_USER가 .env에 설정되어 있지 않습니다}"
RALPH_IMAGE="${RALPH_IMAGE:-ralph-claude}"
NTFY_PORT="${NTFY_PORT:-8095}"

echo "ralph 환경 확인: ${UBUNTU_SSH_USER}@${UBUNTU_HOST} ..."

# ralph 빌드에 필요한 파일만 전송 (Containerfile + scripts/lib)
REMOTE_BUILD_DIR="/tmp/ralph-build-$$"
scp -q -r "${PROJECT_DIR}/infra/ralph" \
  "${UBUNTU_SSH_USER}@${UBUNTU_HOST}:${REMOTE_BUILD_DIR}"

ssh "${UBUNTU_SSH_USER}@${UBUNTU_HOST}" "
  set -euo pipefail

  # Node.js 22+ 확인
  if ! command -v node &>/dev/null; then
    echo 'Error: Node.js가 설치되어 있지 않습니다. Node.js 22+를 먼저 설치하세요.' >&2
    exit 1
  fi
  NODE_MAJOR=\$(node -e 'process.stdout.write(process.version.slice(1).split(\".\")[0])')
  if [ \"\${NODE_MAJOR}\" -lt 22 ]; then
    echo \"Error: Node.js 22+ 필요. 현재: \$(node --version)\" >&2
    exit 1
  fi
  echo \"Node.js: \$(node --version) ✓\"

  # Docker 또는 Podman 확인
  if command -v docker &>/dev/null; then
    CONTAINER_CLI=docker
    echo \"Docker: \$(docker --version | head -1) ✓\"
  elif command -v podman &>/dev/null; then
    CONTAINER_CLI=podman
    echo \"Podman: \$(podman --version) ✓\"
  else
    echo 'Error: docker 또는 podman이 필요합니다' >&2
    exit 1
  fi

  # ralph 이미지 빌드
  echo 'ralph 이미지 빌드 중...'
  \${CONTAINER_CLI} build -t ${RALPH_IMAGE} \
    -f ${REMOTE_BUILD_DIR}/Containerfile \
    ${REMOTE_BUILD_DIR}
  echo \"ralph 이미지 빌드 완료 ✓\"

  rm -rf ${REMOTE_BUILD_DIR}
"

echo ""
echo "설정 완료."
echo ""
echo "=== 다음 단계 (수동) ==="
echo ""
echo "1. Claude 로그인 (Ubuntu에서 한 번만):"
echo "   ssh ${UBUNTU_SSH_USER}@${UBUNTU_HOST}"
echo "   podman run --rm -it --userns=keep-id -e HOME=/tmp/claude-home \\"
echo "     -v \"\$HOME/.claude:/tmp/claude-home/.claude\" \\"
echo "     -v \"\$HOME/.claude.json:/tmp/claude-home/.claude.json\" \\"
echo "     ${RALPH_IMAGE} login"
echo ""
echo "2. openclaw-private 복사 + .env 설정:"
echo "   rsync -a --exclude='.env' --exclude='node_modules' \\"
echo "     ${PROJECT_DIR}/ ${UBUNTU_SSH_USER}@${UBUNTU_HOST}:~/openclaw-private/"
echo "   ssh ${UBUNTU_SSH_USER}@${UBUNTU_HOST}"
echo "   cd ~/openclaw-private && cp .env.example .env"
echo "   # NTFY_URL=http://localhost:${NTFY_PORT} 으로 설정 (ntfy가 로컬에서 실행 중)"
echo ""
echo "3. ralph 워처 시작:"
echo "   ssh ${UBUNTU_SSH_USER}@${UBUNTU_HOST}"
echo "   cd ~/openclaw-private && pnpm ralph:start-projects"
