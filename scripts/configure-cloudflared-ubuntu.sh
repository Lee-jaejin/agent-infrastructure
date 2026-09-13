#!/bin/bash
# Cloudflare Tunnel 설정 파일 작성과 서비스 등록 (#18)
#
# setup-cloudflared-ubuntu.sh 로 설치하고 터널을 만든 뒤 실행
#
# 전제 조건:
#   - 리눅스에 cloudflared 설치 완료
#   - cloudflared tunnel login 과 create 완료
#   - .env 에 UBUNTU_HOST, UBUNTU_SSH_USER, TUNNEL_HOSTNAME, TUNNEL_NAME 설정
#
# 사용법:
#   ./scripts/configure-cloudflared-ubuntu.sh
#
# 이 스크립트는 준비까지만 수행
# 마지막에 출력하는 명령을 사용자가 직접 실행해 설치를 마무리

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
STAGE="/tmp/cloudflared-config"
LOCAL_STAGE="${HOME}/.cache/cloudflared-config"

# 자격 증명 사본이 남지 않도록 종료 시 삭제
trap 'rm -rf "${LOCAL_STAGE}"' EXIT
rm -rf "${LOCAL_STAGE}"; mkdir -p "${LOCAL_STAGE}"

echo "=== 터널 설정: ${REMOTE} ==="

# 터널 ID 는 이름으로 조회. 하드코딩하면 터널을 다시 만들 때 어긋남
TUNNEL_ID=$(ssh "${REMOTE}" "cloudflared tunnel list --output json 2>/dev/null" \
    | python3 -c "
import sys, json
name = sys.argv[1]
for t in json.load(sys.stdin):
    if t.get('name') == name:
        print(t['id'])
        break
" "${TUNNEL_NAME}")

if [[ -z "${TUNNEL_ID}" ]]; then
    echo "터널을 찾을 수 없습니다: ${TUNNEL_NAME}" >&2
    exit 1
fi
echo "  터널 ID: ${TUNNEL_ID}"
echo "  공개 이름: ${TUNNEL_HOSTNAME}"

# ingress 는 위에서부터 평가되고 마지막은 반드시 포괄 규칙이어야 함
echo "[1/3] 설정 파일 작성"
{
    echo "tunnel: ${TUNNEL_ID}"
    echo "credentials-file: /etc/cloudflared/${TUNNEL_ID}.json"
    echo ""
    echo "# 연결이 끊겨도 붙어 있던 요청을 정리할 시간 확보"
    echo "grace-period: 30s"
    echo ""
    echo "ingress:"
    echo "  # SSH 만 통과. 다른 서비스를 열려면 여기에 규칙 추가"
    echo "  - hostname: ${TUNNEL_HOSTNAME}"
    echo "    service: ssh://localhost:22"
    echo "  # 규칙에 안 걸리는 요청은 거절. 이 줄이 없으면 cloudflared 가 기동 실패"
    echo "  - service: http_status:404"
} > "${LOCAL_STAGE}/config.yml"
sed 's/^/  /' "${LOCAL_STAGE}/config.yml"

echo "[2/3] 부트스트랩 스크립트 작성"
{
    echo '#!/bin/bash'
    echo '# 리눅스에서 root 로 실행'
    echo 'set -euo pipefail'
    echo ""
    echo "TUNNEL_ID=\"${TUNNEL_ID}\""
    echo "SRC=\"${STAGE}\""
    echo "CRED_SRC=\"/home/${UBUNTU_SSH_USER}/.cloudflared/${TUNNEL_ID}.json\""
    echo ""
    echo 'echo "[1/4] 설정 배치"'
    echo 'install -d -m 755 /etc/cloudflared'
    echo 'install -m 644 "${SRC}/config.yml" /etc/cloudflared/config.yml'
    echo ""
    echo 'echo "[2/4] 자격 증명 복사"'
    echo '# 자격 증명이 유출되면 그 터널 이름으로 들어올 수 있어 노출을 최소화'
    echo '# 서비스가 nobody 로 돌아 그룹 읽기만 허용'
    echo 'install -m 640 -g nogroup "${CRED_SRC}" "/etc/cloudflared/${TUNNEL_ID}.json"'
    echo ""
    echo 'echo "[3/4] systemd 유닛 등록"'
    echo 'cat > /etc/systemd/system/cloudflared.service <<UNIT'
    echo '[Unit]'
    echo 'Description=Cloudflare Tunnel'
    echo 'After=network-online.target'
    echo 'Wants=network-online.target'
    echo ''
    echo '[Service]'
    echo 'Type=notify'
    echo 'ExecStart=/usr/bin/cloudflared --config /etc/cloudflared/config.yml --no-autoupdate tunnel run'
    echo 'Restart=always'
    echo 'RestartSec=5'
    echo '# 밖으로만 연결하는 outbound 전용이라 권한을 낮춰도 동작'
    echo 'User=nobody'
    echo 'Group=nogroup'
    echo 'NoNewPrivileges=true'
    echo 'ProtectSystem=strict'
    echo 'ProtectHome=true'
    echo 'PrivateTmp=true'
    echo ''
    echo '[Install]'
    echo 'WantedBy=multi-user.target'
    echo 'UNIT'
    echo ""
    echo 'systemctl daemon-reload'
    echo 'systemctl enable --now cloudflared'
    echo ""
    echo 'echo "[4/4] 기동 확인"'
    echo 'sleep 8'
    echo 'systemctl is-active cloudflared'
    echo 'journalctl -u cloudflared -n 5 --no-pager | tail -5'
    echo 'rm -rf "${SRC}"'
} > "${LOCAL_STAGE}/bootstrap.sh"

echo "[3/3] 전송"
ssh "${REMOTE}" "rm -rf ${STAGE} && mkdir -p ${STAGE}"
scp -q "${LOCAL_STAGE}/config.yml" "${LOCAL_STAGE}/bootstrap.sh" "${REMOTE}:${STAGE}/"
ssh "${REMOTE}" "chmod +x ${STAGE}/bootstrap.sh"

echo ""
echo "준비 완료. 아래를 실행하세요."
echo ""
echo "  ssh -t ${REMOTE} 'sudo bash ${STAGE}/bootstrap.sh'"
echo ""
echo "설치 후 접속하는 쪽(맥북)에 cloudflared 를 깔고 SSH 설정에 아래를 추가하세요."
echo ""
echo "  brew install cloudflared"
echo ""
echo "  # ~/.ssh/config"
echo "  Host ${TUNNEL_HOSTNAME}"
echo "  	User ${UBUNTU_SSH_USER}"
echo "  	ProxyCommand \$(command -v cloudflared) access ssh --hostname %h"
echo ""
echo "접속은 평소처럼 ssh ${TUNNEL_HOSTNAME} 로 합니다."
echo ""
echo "중요: Cloudflare Access 정책을 반드시 거세요."
echo "  걸지 않으면 이 이름을 아는 사람이 SSH 포트에 도달합니다."
