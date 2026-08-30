#!/bin/bash
# ntfy 를 상시 가동 리눅스에 배포
#
# 맥북은 뚜껑을 닫으면 잠들어 알림 서버도 함께 멈춤
# 상시 켜진 리눅스로 옮겨 알림이 맥북 상태와 무관하게 유지되게 함
#
# 전제 조건:
#   - .env 에 UBUNTU_HOST, UBUNTU_SSH_USER 설정
#   - 맥북에서 리눅스로 SSH 공개키 인증이 되는 상태
#
# 사용법:
#   pnpm ntfy:ubuntu:deploy
#
# 이 스크립트는 sudo 가 필요 없는 준비 단계까지만 수행
# 마지막에 출력하는 부트스트랩 명령을 사용자가 직접 실행해 설치를 마무리

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a; source "${ENV_FILE}"; set +a
fi

UBUNTU_HOST="${UBUNTU_HOST:?UBUNTU_HOST 이 .env 에 설정되어 있지 않습니다}"
UBUNTU_SSH_USER="${UBUNTU_SSH_USER:?UBUNTU_SSH_USER 가 .env 에 설정되어 있지 않습니다}"
NTFY_PORT="${NTFY_PORT:-8095}"
REMOTE="${UBUNTU_SSH_USER}@${UBUNTU_HOST}"
STAGE="/tmp/ntfy-deploy"

# 이미지는 digest 로 고정. 태그로 두면 재기동 때 상위 버전이 올라와 동작이 달라질 수 있음
NTFY_IMAGE="${NTFY_IMAGE:-docker.io/binwiederhier/ntfy:v2.11.0}"

echo "=== ntfy 배포 준비: ${REMOTE} ==="

# podman 3.4.4 에는 compose 하위 명령이 없고 docker 는 sudo 가 필요해
# compose 대신 systemd 유닛에 podman run 으로 구성
cat > "/tmp/ntfy-bootstrap.sh" <<BOOTSTRAP
#!/bin/bash
# 리눅스에서 root 로 실행
set -euo pipefail

echo "[1/3] 이미지 준비"
podman pull -q "${NTFY_IMAGE}" >/dev/null
install -d -m 755 /var/lib/ntfy

echo "[2/3] systemd 유닛 등록"
cat > /etc/systemd/system/ntfy.service <<UNIT
[Unit]
Description=ntfy push notification server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# 재기동 시 남은 컨테이너가 이름을 잡고 있으면 기동 실패하므로 먼저 제거
ExecStartPre=-/usr/bin/podman rm -f ntfy
ExecStart=/usr/bin/podman run --rm --name ntfy \\
    --network host \\
    -v /var/lib/ntfy:/var/lib/ntfy \\
    -e TZ=Asia/Seoul \\
    ${NTFY_IMAGE} serve --listen-http :${NTFY_PORT}
ExecStop=/usr/bin/podman stop -t 10 ntfy
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now ntfy

echo "[3/3] 기동 확인"
sleep 5
systemctl is-active ntfy
curl -sf "http://localhost:${NTFY_PORT}/v1/health" && echo
BOOTSTRAP

ssh "${REMOTE}" "rm -rf ${STAGE} && mkdir -p ${STAGE}"
scp -q "/tmp/ntfy-bootstrap.sh" "${REMOTE}:${STAGE}/bootstrap.sh"
ssh "${REMOTE}" "chmod +x ${STAGE}/bootstrap.sh"
rm -f "/tmp/ntfy-bootstrap.sh"

echo "준비 완료. 아래 명령을 실행해 설치를 마치세요."
echo ""
echo "  ssh -t ${REMOTE} 'sudo bash ${STAGE}/bootstrap.sh'"
echo ""
echo "설치 후 .env 를 아래처럼 바꾸세요."
echo "  NTFY_URL=http://${UBUNTU_HOST}:${NTFY_PORT}"
