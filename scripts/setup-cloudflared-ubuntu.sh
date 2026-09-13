#!/bin/bash
# Cloudflare Tunnel 로 리눅스에 외부 접근 경로 마련 (#18)
#
# 안에서 밖으로 연결을 걸어 들어오는 포트를 열지 않는다
# 공유기 설정이 필요 없고 공인 IP 가 노출되지 않아 스캔 표적에서 빠진다
#
# 전제 조건:
#   - Cloudflare 계정에 도메인이 올라가 있을 것
#   - .env 에 UBUNTU_HOST, UBUNTU_SSH_USER, TUNNEL_HOSTNAME 설정
#
# 사용법:
#   ./scripts/setup-cloudflared-ubuntu.sh
#
# 이 스크립트는 설치까지만 한다. 터널 생성은 브라우저 인증이 필요해
# 마지막에 출력하는 명령을 사용자가 직접 실행한다

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a; source "${ENV_FILE}"; set +a
fi

UBUNTU_HOST="${UBUNTU_HOST:?UBUNTU_HOST 이 .env 에 설정되어 있지 않습니다}"
UBUNTU_SSH_USER="${UBUNTU_SSH_USER:?UBUNTU_SSH_USER 가 .env 에 설정되어 있지 않습니다}"
TUNNEL_HOSTNAME="${TUNNEL_HOSTNAME:?TUNNEL_HOSTNAME 이 .env 에 설정되어 있지 않습니다}"
TUNNEL_NAME="${TUNNEL_NAME:-home-linux}"
REMOTE="${UBUNTU_SSH_USER}@${UBUNTU_HOST}"
STAGE="/tmp/cloudflared-setup"

echo "=== cloudflared 설치 준비: ${REMOTE} ==="
echo "  터널 이름: ${TUNNEL_NAME}"
echo "  공개 이름: ${TUNNEL_HOSTNAME}"

# 설치는 root 가 필요하므로 부트스트랩으로 분리
cat > "/tmp/cf-bootstrap.sh" <<'BOOTSTRAP'
#!/bin/bash
# 리눅스에서 root 로 실행. cloudflared 설치까지만 담당
set -euo pipefail

if command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared 이미 설치됨: $(cloudflared --version)"
    exit 0
fi

echo "Cloudflare 저장소 등록"
mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    > /usr/share/keyrings/cloudflare-main.gpg
chmod 644 /usr/share/keyrings/cloudflare-main.gpg

# 배포판 코드명을 직접 읽어 저장소 라인을 만든다. 하드코딩하면 업그레이드 후 깨짐
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared ${CODENAME} main" \
    > /etc/apt/sources.list.d/cloudflared.list

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cloudflared
cloudflared --version
BOOTSTRAP

ssh "${REMOTE}" "rm -rf ${STAGE} && mkdir -p ${STAGE}"
scp -q "/tmp/cf-bootstrap.sh" "${REMOTE}:${STAGE}/bootstrap.sh"
ssh "${REMOTE}" "chmod +x ${STAGE}/bootstrap.sh"
rm -f "/tmp/cf-bootstrap.sh"

echo ""
echo "준비 완료. 아래를 순서대로 실행하세요."
echo ""
echo "1. cloudflared 설치 (root 필요)"
echo "   ssh -t ${REMOTE} 'sudo bash ${STAGE}/bootstrap.sh'"
echo ""
echo "2. Cloudflare 로그인 (브라우저 인증, 한 번만)"
echo "   ssh -t ${REMOTE} 'cloudflared tunnel login'"
echo "   출력된 URL 을 브라우저에서 열어 도메인을 선택하세요"
echo ""
echo "3. 터널 생성"
echo "   ssh -t ${REMOTE} 'cloudflared tunnel create ${TUNNEL_NAME}'"
echo ""
echo "4. DNS 연결"
echo "   ssh -t ${REMOTE} 'cloudflared tunnel route dns ${TUNNEL_NAME} ${TUNNEL_HOSTNAME}'"
echo ""
echo "여기까지 끝나면 알려주세요. 설정 파일 작성과 서비스 등록은 제가 이어서 합니다."
