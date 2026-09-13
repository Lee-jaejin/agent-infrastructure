#!/bin/bash
# headscale TLS 인증서 생성과 갱신 (#11)
#
# 코디네이터는 리눅스로 옮겨갔지만 인증서는 이 리포에서 만들어 배포한다
# 그래서 이 스크립트가 도는 곳과 인증서가 쓰일 곳이 다르다
#
# 사용법:
#   ./scripts/setup-certs.sh init     # CA 와 서버 인증서를 새로 생성
#   ./scripts/setup-certs.sh renew    # CA 는 두고 서버 인증서만 재발급
#   ./scripts/setup-certs.sh show     # 현재 SAN 과 유효기간 확인
#
# renew 를 두는 이유:
#   CA 를 새로 만들면 모든 노드에 다시 설치해야 한다. 코디네이터 주소가 바뀌었을 뿐인데
#   그 작업을 반복할 이유가 없어, 서버 인증서만 다시 서명하는 경로를 둔다
#
# SAN 지정:
#   HEADSCALE_SAN   쉼표로 구분한 목록 (e.g., "10.0.0.5,headscale.example")
#                   미지정 시 .env 의 HEADSCALE_HOST_IP 사용
#   renew 는 기존 인증서의 SAN 을 두고 새 항목을 더한다
#   되돌릴 때 예전 주소로도 붙어야 해서다. 비우려면 --replace

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
CERTS_DIR="${PROJECT_DIR}/infra/headscale/certs"

ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a; source "${ENV_FILE}"; set +a
fi

CMD="${1:-}"
REPLACE=0
[[ "${2:-}" == "--replace" ]] && REPLACE=1

CA_CRT="${CERTS_DIR}/ca.crt"
CA_KEY="${CERTS_DIR}/ca.key"
SRV_CRT="${CERTS_DIR}/headscale.crt"
SRV_KEY="${CERTS_DIR}/headscale.key"
SRV_CNF="${CERTS_DIR}/server-openssl.cnf"
CA_CNF="${CERTS_DIR}/ca-openssl.cnf"

log() { printf '[certs] %s\n' "$*"; }

# 현재 인증서의 SAN 을 "DNS:이름" / "IP:주소" 한 줄씩으로 출력
read_existing_san() {
    [[ -f "${SRV_CRT}" ]] || return 0
    openssl x509 -in "${SRV_CRT}" -noout -ext subjectAltName 2>/dev/null \
        | tr ',' '\n' \
        | sed -n -e 's/.*DNS:\([^ ,]*\).*/DNS:\1/p' -e 's/.*IP Address:\([^ ,]*\).*/IP:\1/p'
}

# 목록을 받아 openssl 설정의 alt_names 절 작성
# DNS 와 IP 는 번호를 따로 매겨야 해서 종류별로 센다
write_san_config() {
    local entries="$1"
    {
        echo "[req]"
        echo "default_bits = 2048"
        echo "prompt = no"
        echo "default_md = sha256"
        echo "distinguished_name = dn"
        echo "req_extensions = v3_req"
        echo ""
        echo "[dn]"
        echo "CN = headscale.local"
        echo ""
        echo "[v3_req]"
        echo "basicConstraints = critical, CA:FALSE"
        echo "keyUsage = critical, digitalSignature, keyEncipherment"
        echo "extendedKeyUsage = serverAuth"
        echo "subjectAltName = @alt_names"
        echo ""
        echo "[alt_names]"
        printf '%s\n' "${entries}" | python3 -c '
import sys

dns_n = ip_n = 0
seen = set()
for line in sys.stdin:
    entry = line.strip()
    if not entry or entry in seen:
        continue
    seen.add(entry)
    kind, _, value = entry.partition(":")
    if kind == "DNS":
        dns_n += 1
        print("DNS.%d = %s" % (dns_n, value))
    elif kind == "IP":
        ip_n += 1
        print("IP.%d = %s" % (ip_n, value))
'
    } > "${SRV_CNF}"
}

# 요청받은 SAN 목록 구성. 항상 들어가는 항목에 사용자 지정분을 더함
build_entries() {
    local wanted=""
    wanted+="DNS:localhost"$'\n'
    wanted+="DNS:headscale.local"$'\n'
    wanted+="IP:127.0.0.1"$'\n'

    local raw="${HEADSCALE_SAN:-${HEADSCALE_HOST_IP:-}}"
    if [[ -z "${raw}" ]]; then
        log "HEADSCALE_SAN 도 HEADSCALE_HOST_IP 도 설정되지 않았습니다" >&2
        log "  코디네이터 주소를 알 수 없어 중단합니다" >&2
        exit 1
    fi

    local item
    while IFS= read -r item; do
        [[ -z "${item}" ]] && continue
        # 숫자와 점으로만 이뤄지면 IP, 아니면 DNS 이름으로 처리
        if [[ "${item}" =~ ^[0-9.]+$ ]]; then
            wanted+="IP:${item}"$'\n'
        else
            wanted+="DNS:${item}"$'\n'
        fi
    # printf 에 개행을 붙이지 않으면 read 가 마지막 항목에서 EOF 로 빠져 그 항목을 버린다
    done < <(printf '%s\n' "${raw}" | tr ',' '\n' | sed 's/^ *//; s/ *$//')

    printf '%s' "${wanted}"
}

ensure_ca_config() {
    [[ -f "${CA_CNF}" ]] && return 0
    # certs 디렉터리가 gitignore 대상이라 새로 받은 리포에는 이 파일이 없다
    log "CA 설정 파일 생성: ${CA_CNF}"
    {
        echo "[req]"
        echo "default_bits = 4096"
        echo "prompt = no"
        echo "default_md = sha256"
        echo "x509_extensions = v3_ca"
        echo "distinguished_name = dn"
        echo ""
        echo "[dn]"
        echo "CN = OpenClaw Headscale Root CA"
        echo ""
        echo "[v3_ca]"
        echo "basicConstraints = critical, CA:TRUE, pathlen:0"
        echo "keyUsage = critical, keyCertSign, cRLSign"
        echo "subjectKeyIdentifier = hash"
    } > "${CA_CNF}"
}

sign_server_cert() {
    local entries="$1"
    write_san_config "${entries}"

    [[ -f "${SRV_KEY}" ]] || openssl genrsa -out "${SRV_KEY}" 2048 2>/dev/null
    openssl req -new -key "${SRV_KEY}" -out "${CERTS_DIR}/headscale.csr" \
        -config "${SRV_CNF}" 2>/dev/null
    openssl x509 -req -days 825 \
        -in "${CERTS_DIR}/headscale.csr" \
        -CA "${CA_CRT}" -CAkey "${CA_KEY}" -CAcreateserial \
        -out "${SRV_CRT}" \
        -extensions v3_req -extfile "${SRV_CNF}" 2>/dev/null
    openssl verify -CAfile "${CA_CRT}" "${SRV_CRT}"
}

cmd_init() {
    if [[ -f "${CA_CRT}" ]]; then
        log "CA 가 이미 있습니다: ${CA_CRT}" >&2
        log "  주소만 바뀐 것이면 renew 를 쓰세요. CA 를 새로 만들면 모든 노드에 재설치가 필요합니다" >&2
        exit 1
    fi
    mkdir -p "${CERTS_DIR}"
    ensure_ca_config

    log "CA 생성"
    openssl genrsa -out "${CA_KEY}" 4096 2>/dev/null
    openssl req -new -x509 -days 3650 -key "${CA_KEY}" -out "${CA_CRT}" -config "${CA_CNF}"

    log "서버 인증서 발급"
    sign_server_cert "$(build_entries)"
    cmd_show
}

cmd_renew() {
    if [[ ! -f "${CA_CRT}" || ! -f "${CA_KEY}" ]]; then
        log "CA 가 없습니다. 먼저 init 을 실행하세요" >&2
        exit 1
    fi

    local entries
    entries="$(build_entries)"
    if [[ "${REPLACE}" -eq 0 ]]; then
        # 기존 SAN 을 앞에 붙여 예전 주소로도 계속 붙게 함
        entries="$(read_existing_san)"$'\n'"${entries}"
    fi

    log "서버 인증서 재발급 (CA 유지)"
    sign_server_cert "${entries}"
    cmd_show
}

cmd_show() {
    if [[ ! -f "${SRV_CRT}" ]]; then
        log "서버 인증서가 없습니다" >&2
        exit 1
    fi
    echo ""
    log "CA 만료:   $(openssl x509 -in "${CA_CRT}" -noout -enddate 2>/dev/null | cut -d= -f2)"
    log "서버 만료: $(openssl x509 -in "${SRV_CRT}" -noout -enddate | cut -d= -f2)"
    log "SAN:"
    read_existing_san | sed 's/^/  /'
    echo ""
    log "설정 파일의 주소는 이 스크립트가 건드리지 않음"
    log "  배포 시점에 deploy-headscale-ubuntu.sh 가 채움"
}

case "${CMD}" in
    init)  cmd_init ;;
    renew) cmd_renew ;;
    show)  cmd_show ;;
    *)     sed -n '2,22p' "$0"; exit 1 ;;
esac
