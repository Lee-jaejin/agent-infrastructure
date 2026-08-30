#!/bin/bash
# 리눅스에 ralph 실행 환경 준비
#
# 워처 스크립트들이 JSON 파싱에 host 의 node 를 쓰므로 리눅스에도 Node 가 필요
# 실행 이미지는 podman 으로 빌드
#
# 이 스크립트가 하는 것:
#   1. Node.js 22 설치 확인 및 설치
#   2. ralph 이미지 빌드
#
# 이 스크립트가 하지 않는 것:
#   - Claude 로그인. 대화형이라 사용자가 직접 수행
#   - 프로젝트 소스 동기화와 projects.json 작성
#
# 전제 조건:
#   - .env 에 UBUNTU_HOST, UBUNTU_SSH_USER 설정
#   - 맥북에서 리눅스로 SSH 공개키 인증이 되는 상태
#
# 사용법:
#   pnpm ralph:ubuntu:setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a; source "${ENV_FILE}"; set +a
fi

UBUNTU_HOST="${UBUNTU_HOST:?UBUNTU_HOST 이 .env 에 설정되어 있지 않습니다}"
UBUNTU_SSH_USER="${UBUNTU_SSH_USER:?UBUNTU_SSH_USER 가 .env 에 설정되어 있지 않습니다}"
RALPH_IMAGE="${RALPH_IMAGE:-ralph-claude}"
REMOTE="${UBUNTU_SSH_USER}@${UBUNTU_HOST}"
STAGE="/tmp/ralph-build"

echo "=== ralph 환경 준비: ${REMOTE} ==="

# 빌드에 필요한 파일만 전송
echo "[1/3] 빌드 파일 전송"
ssh "${REMOTE}" "rm -rf ${STAGE} && mkdir -p ${STAGE}"
scp -q -r "${PROJECT_DIR}/infra/ralph/." "${REMOTE}:${STAGE}/"
ssh "${REMOTE}" "ls -1 ${STAGE}" | sed 's/^/  /'

# Node 설치는 root 가 필요하므로 부트스트랩으로 분리
echo "[2/3] 부트스트랩 스크립트 생성"
cat > "/tmp/ralph-bootstrap.sh" <<BOOTSTRAP
#!/bin/bash
# 리눅스에서 root 로 실행. Node.js 22 설치까지만 담당
set -euo pipefail

if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=\$(node -e 'process.stdout.write(process.version.slice(1).split(".")[0])')
else
    NODE_MAJOR=0
fi

if [ "\${NODE_MAJOR}" -lt 22 ]; then
    echo "Node.js 22 설치"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl gnupg
    install -d -m 755 /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \\
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    chmod 644 /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \\
        > /etc/apt/sources.list.d/nodesource.list
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs
else
    echo "Node.js 이미 설치됨"
fi

node --version
# pnpm 은 node 에 딸려오는 corepack 으로 활성화. 별도 설치 불필요
corepack enable pnpm 2>/dev/null || true
BOOTSTRAP

scp -q "/tmp/ralph-bootstrap.sh" "${REMOTE}:${STAGE}/bootstrap.sh"
ssh "${REMOTE}" "chmod +x ${STAGE}/bootstrap.sh"
rm -f "/tmp/ralph-bootstrap.sh"

echo "[3/3] 준비 완료"
echo ""
echo "1. Node 설치 (root 필요)"
echo "   ssh -t ${REMOTE} 'sudo bash ${STAGE}/bootstrap.sh'"
echo ""
echo "2. 이미지 빌드 (root 불필요, rootless podman)"
echo "   ssh ${REMOTE} 'podman build -t ${RALPH_IMAGE} -f ${STAGE}/Containerfile ${STAGE}'"
echo ""
echo "3. Claude 로그인 (대화형, 한 번만)"
echo "   ssh -t ${REMOTE} 'podman run --rm -it --userns=keep-id -e HOME=/tmp/claude-home \\"
echo "     -v \"\$HOME/.claude:/tmp/claude-home/.claude\" \\"
echo "     -v \"\$HOME/.claude.json:/tmp/claude-home/.claude.json\" \\"
echo "     ${RALPH_IMAGE} login'"
echo ""
echo "4. 프로젝트 정의와 소스 동기화 후 워처 시작"
echo "   infra/ralph/projects.json 작성 필요"
