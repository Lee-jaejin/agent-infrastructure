#!/bin/bash
# headscale 을 상시 가동 리눅스로 이전
#
# 맥북은 뚜껑을 닫으면 잠들어 코디네이터도 함께 멈춤
# 상시 켜진 리눅스로 옮겨 VPN 이 맥북 상태와 무관하게 유지되게 함
#
# 전제 조건:
#   - .env 에 UBUNTU_HOST, UBUNTU_SSH_USER 설정
#   - 맥북에서 리눅스로 SSH 공개키 인증이 되는 상태
#   - 서버 인증서 SAN 에 리눅스 IP 포함 (scripts/setup-certs.sh 참고)
#
# 사용법:
#   ./scripts/deploy-headscale-ubuntu.sh
#   ./scripts/deploy-headscale-ubuntu.sh --force   # 안전 검사 무시
#
# 한 방향 이전을 전제로 만들었다. 이전이 끝난 뒤 다시 실행하면 리눅스의
# 등록 데이터를 맥북 사본으로 덮으므로, 기본 동작은 거부다
#
# 이 스크립트는 sudo 가 필요 없는 준비 단계까지만 수행
# 마지막에 출력하는 부트스트랩 명령을 사용자가 직접 실행해 설치를 마무리

set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
HS_DIR="${PROJECT_DIR}/infra/headscale"

ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a; source "${ENV_FILE}"; set +a
fi

UBUNTU_HOST="${UBUNTU_HOST:?UBUNTU_HOST 이 .env 에 설정되어 있지 않습니다}"
UBUNTU_SSH_USER="${UBUNTU_SSH_USER:?UBUNTU_SSH_USER 가 .env 에 설정되어 있지 않습니다}"
REMOTE="${UBUNTU_SSH_USER}@${UBUNTU_HOST}"
# 맥의 podman 은 VM 안에서 돌아 /tmp 를 못 봄. 반출용 로컬 경로는 홈 밑에 배치
LOCAL_STAGE="${HOME}/.cache/headscale-deploy"
STAGE="/tmp/headscale-deploy"

# 스테이징에는 서버 개인키와 노드 등록 DB 사본이 담김
# 전송 도중 실패해도 남지 않도록 종료 시 삭제
trap 'rm -rf "${LOCAL_STAGE}"' EXIT

# 이미지는 맥북에서 쓰던 것과 같은 digest 로 고정
# 태그로 두면 옮기는 사이 상위 버전이 올라와 DB 스키마가 어긋날 수 있음
HS_IMAGE="${HS_IMAGE:-docker.io/headscale/headscale@sha256:51b1b9182bb6219e97374fa89af6b9320d6f87ecc739e328d5357ea4fa7a5ce3}"

echo "=== headscale 이전 준비: ${REMOTE} ==="

# 0. 원격에 이미 설치돼 있으면 중단
# 이전이 끝난 상태에서 다시 실행하면 리눅스의 최신 등록 데이터를 덮는다.
# 맥북 컨테이너를 멈추기 전에 확인해야 실수해도 되돌릴 것이 없다
echo "[0/5] 원격 설치 여부 확인"
REMOTE_INSTALLED=$(ssh "${REMOTE}" \
    'test -f /etc/headscale/config.yaml && echo yes || echo no' 2>/dev/null || echo unknown)
if [[ "${REMOTE_INSTALLED}" == "yes" ]]; then
    if [[ "${FORCE}" -eq 1 ]]; then
        echo "  이미 설치돼 있으나 --force 로 계속 진행"
    else
        echo "" >&2
        echo "중단: ${REMOTE} 에 headscale 이 이미 설치돼 있습니다." >&2
        echo "  그대로 진행하면 그쪽의 등록 데이터를 이 맥북 사본으로 덮습니다." >&2
        echo "  이전 이후 등록한 노드와 발급한 키가 사라집니다." >&2
        echo "" >&2
        echo "  주소만 바꾸려면 인증서와 설정만 갱신하세요. 등록 데이터는 건드리지 않습니다." >&2
        echo "  정말 덮어써야 하면 --force 를 붙이세요." >&2
        exit 1
    fi
else
    echo "  설치 흔적 없음, 계속 진행"
fi

# 1. 맥북 headscale 정지 후 상태 반출
# 컨테이너가 도는 중 sqlite 를 복사하면 쓰다 만 상태가 섞이므로 먼저 정지
echo "[1/5] 맥북 headscale 정지 및 상태 반출"
podman stop headscale >/dev/null 2>&1 || true
rm -rf "${LOCAL_STAGE}"; mkdir -p "${LOCAL_STAGE}/state"
podman run --rm -v agent-infrastructure_headscale-data:/d:ro -v "${LOCAL_STAGE}/state:/out" \
    docker.io/library/alpine:latest sh -c 'cp -a /d/. /out/' >/dev/null
ls -1 "${LOCAL_STAGE}/state" | sed 's/^/  /'

# 반출한 DB 에 노드가 없으면 빈 상태를 밀어 넣는 것이므로 중단.
# 볼륨이 지워졌거나 이름이 바뀌면 podman 이 빈 볼륨을 새로 만들어 조용히 통과한다
DB="${LOCAL_STAGE}/state/db.sqlite"
if [[ -f "${DB}" ]]; then
    NODE_COUNT=$(sqlite3 "${DB}" 'select count(*) from nodes;' 2>/dev/null || echo 0)
else
    NODE_COUNT=0
fi
echo "  반출된 노드 수: ${NODE_COUNT}"
if [[ "${NODE_COUNT}" -eq 0 ]]; then
    if [[ "${FORCE}" -eq 1 ]]; then
        echo "  노드가 없으나 --force 로 계속 진행"
    else
        echo "" >&2
        echo "중단: 반출된 등록 데이터에 노드가 없습니다." >&2
        echo "  볼륨이 지워졌거나 이름이 바뀌면 빈 볼륨이 새로 생겨 이 상태가 됩니다." >&2
        echo "  이대로 진행하면 리눅스의 등록을 빈 상태로 덮습니다." >&2
        echo "" >&2
        echo "  처음 구축하는 경우라면 --force 를 붙이세요." >&2
        exit 1
    fi
fi

# 2. 설정과 인증서 준비
echo "[2/5] 설정과 인증서 준비"
mkdir -p "${LOCAL_STAGE}/config" "${LOCAL_STAGE}/certs"
sed -e "s|^server_url:.*|server_url: https://${UBUNTU_HOST}:8080|" \
    -e "s|^    ipv4:.*|    ipv4: ${UBUNTU_HOST}|" \
    "${HS_DIR}/config/config.yaml" > "${LOCAL_STAGE}/config/config.yaml"
cp "${HS_DIR}/acl.json" "${LOCAL_STAGE}/config/acl.json"
# 서버 개인키도 함께 전송. 리눅스가 이 키로 TLS 를 서비스하므로 필수
cp "${HS_DIR}/certs/headscale.crt" "${HS_DIR}/certs/headscale.key" "${HS_DIR}/certs/ca.crt" "${LOCAL_STAGE}/certs/"
grep -n "server_url\|    ipv4" "${LOCAL_STAGE}/config/config.yaml" | sed 's/^/  /'

# 3. 원격 부트스트랩 스크립트 생성
echo "[3/5] 부트스트랩 스크립트 생성"
cat > "${LOCAL_STAGE}/bootstrap.sh" <<BOOTSTRAP
#!/bin/bash
# 리눅스에서 root 로 실행. podman 설치부터 서비스 등록까지 수행
set -euo pipefail

HS_IMAGE="${HS_IMAGE}"
STAGE="${STAGE}"

echo "[1/5] podman 설치"
if ! command -v podman >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq podman
fi
podman --version

echo "[2/5] 설정 배치"
install -d -m 755 /etc/headscale /etc/headscale/certs
install -m 644 "\${STAGE}/config/config.yaml" /etc/headscale/config.yaml
install -m 644 "\${STAGE}/config/acl.json" /etc/headscale/acl.json
install -m 644 "\${STAGE}/certs/headscale.crt" "\${STAGE}/certs/ca.crt" /etc/headscale/certs/
# 서버 개인키는 root 만 읽도록 제한
install -m 600 "\${STAGE}/certs/headscale.key" /etc/headscale/certs/

echo "[3/5] 상태 복원"
install -d -m 755 /var/lib/headscale
cp -a "\${STAGE}/state/." /var/lib/headscale/
chmod 600 /var/lib/headscale/*.key 2>/dev/null || true
ls -1 /var/lib/headscale | sed 's/^/  /'

echo "[4/5] systemd 유닛 등록"
podman pull -q "\${HS_IMAGE}" >/dev/null
cat > /etc/systemd/system/headscale.service <<UNIT
[Unit]
Description=headscale VPN coordinator
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# 재기동 시 남은 컨테이너가 이름을 잡고 있으면 기동 실패하므로 먼저 제거
ExecStartPre=-/usr/bin/podman rm -f headscale
ExecStart=/usr/bin/podman run --rm --name headscale \\
    --network host \\
    -v /etc/headscale/config.yaml:/etc/headscale/config.yaml:ro \\
    -v /etc/headscale/acl.json:/etc/headscale/acl.json:ro \\
    -v /etc/headscale/certs:/etc/headscale/certs:ro \\
    -v /var/lib/headscale:/var/lib/headscale \\
    -e TZ=Asia/Seoul \\
    \${HS_IMAGE} serve
ExecStop=/usr/bin/podman stop -t 10 headscale
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now headscale

echo "[5/5] 기동 확인"
sleep 6
systemctl is-active headscale
curl -sS --cacert /etc/headscale/certs/ca.crt "https://\$(hostname -I | awk '{print \$1}'):8080/health" || true
echo

# 정식 설치본이 /etc/headscale 과 /var/lib/headscale 에 있으므로 스테이징 사본은 남길 이유가 없음
# 개인키와 등록 DB 가 /tmp 에 남지 않도록 마지막에 삭제
rm -rf "\${STAGE}"
echo "스테이징 정리 완료: \${STAGE}"
BOOTSTRAP
chmod +x "${LOCAL_STAGE}/bootstrap.sh"

# 4. 리눅스로 전송
echo "[4/5] 리눅스로 전송"
ssh "${REMOTE}" "rm -rf ${STAGE} && mkdir -p ${STAGE}"
scp -q -r "${LOCAL_STAGE}/." "${REMOTE}:${STAGE}/"
ssh "${REMOTE}" "ls -1 ${STAGE}" | sed 's/^/  /'

echo ""
echo "준비 완료. 아래 명령을 실행해 설치를 마치세요."
echo ""
echo "  ssh -t ${REMOTE} 'sudo bash ${STAGE}/bootstrap.sh'"
echo ""
echo "설치 후 각 노드를 새 주소로 재접속시킵니다."
echo "  tailscale up --login-server=https://${UBUNTU_HOST}:8080 --authkey=<키> --accept-routes --reset --force-reauth"
