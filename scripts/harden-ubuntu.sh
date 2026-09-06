#!/bin/bash
# 리눅스 서버 노출면 축소 (#14)
#
# 방화벽을 기본 차단으로 두고 필요한 경로만 연다
# 개별 서비스의 바인딩을 하나씩 고치는 것보다 실수가 적고,
# 새 서비스가 실수로 열려도 막힌다
#
# 리눅스에서 root 로 실행:
#   sudo bash harden-ubuntu.sh
#
# env 오버라이드:
#   LAN_CIDR      LAN 대역 (미지정 시 기본 경로에서 추론)
#   VPN_IF        VPN 인터페이스 (기본 tailscale0)
#   KEEP_RDP      1 이면 LAN 에서 RDP 허용 (기본 1)
#   DISABLE_PW_AUTH  1 이면 SSH 비밀번호 인증 차단 (기본 1)

set -euo pipefail

VPN_IF="${VPN_IF:-tailscale0}"
KEEP_RDP="${KEEP_RDP:-1}"
DISABLE_PW_AUTH="${DISABLE_PW_AUTH:-1}"

log() { printf '[harden] %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { log "root 로 실행 필요"; exit 1; }

# LAN 대역 추론. 기본 경로가 나가는 인터페이스의 주소에서 뽑음
if [ -z "${LAN_CIDR:-}" ]; then
    LAN_IF=$(ip route show default | awk '{print $5; exit}')
    LAN_CIDR=$(ip -4 -o addr show dev "$LAN_IF" scope global | awk '{print $4; exit}')
    # 호스트 주소를 대역 주소로 바꿈 (e.g., 10.0.0.5/24 -> 10.0.0.0/24)
    LAN_CIDR=$(python3 -c "import ipaddress,sys; print(ipaddress.ip_network(sys.argv[1], strict=False))" "$LAN_CIDR")
fi
log "LAN 대역: ${LAN_CIDR}"
log "VPN 인터페이스: ${VPN_IF}"

echo
log "[1/4] ufw 설치"
if ! command -v ufw >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw
fi
ufw --version | head -1

echo
log "[2/4] 규칙 작성"
# 순서가 중요하다. 기본 차단을 켜기 전에 SSH 를 먼저 허용하지 않으면
# 원격 접근이 끊겨 물리 접근이 필요해진다
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null

# SSH 를 가장 먼저. 이 줄이 빠지면 이후 enable 에서 스스로를 잠근다
ufw allow from "${LAN_CIDR}" to any port 22 proto tcp comment 'SSH (LAN)' >/dev/null
log "  SSH 허용 (LAN)"

# VPN 인터페이스는 통째로 허용. 이미 인증된 노드만 들어온다
ufw allow in on "${VPN_IF}" comment 'VPN 전체' >/dev/null
log "  VPN 인터페이스 전체 허용"

# headscale 제어 평면과 중계는 LAN 에서 닿아야 한다.
# 노드가 VPN 을 맺기 전에 쓰는 경로라 VPN 안에 둘 수 없다
ufw allow from "${LAN_CIDR}" to any port 8080 proto tcp comment 'headscale' >/dev/null
ufw allow from "${LAN_CIDR}" to any port 3478 proto udp comment 'STUN' >/dev/null
log "  headscale 8080/tcp, STUN 3478/udp 허용 (LAN)"

# WireGuard 실 데이터 포트. 막으면 직접 연결이 실패해 전부 중계를 탄다
ufw allow 41641/udp comment 'WireGuard 직접 연결' >/dev/null
log "  WireGuard 41641/udp 허용"

if [ "${KEEP_RDP}" = "1" ]; then
    # 원격 데스크톱을 실제로 쓰고 있어 LAN 한정으로 남김
    # 쓰지 않게 되면 KEEP_RDP=0 으로 다시 실행
    ufw allow from "${LAN_CIDR}" to any port 3389 proto tcp comment 'RDP (LAN)' >/dev/null
    log "  RDP 허용 (LAN 한정)"
else
    log "  RDP 미허용"
fi

echo
log "[3/4] 방화벽 활성화"
ufw --force enable >/dev/null
systemctl enable ufw >/dev/null 2>&1 || true
ufw status verbose | head -20

echo
log "[4/4] SSH 비밀번호 인증"
if [ "${DISABLE_PW_AUTH}" = "1" ]; then
    # 세 머신 모두 키 인증이 되는 것을 확인한 뒤 끈다
    # 되돌리려면 아래 파일을 지우고 sshd 재시작
    install -d -m 755 /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/99-harden.conf <<'EOF'
# 무차별 대입을 무의미하게 만들기 위해 키 인증만 허용
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
    if sshd -t 2>/dev/null; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd
        log "  비밀번호 인증 차단, 키 인증만 허용"
    else
        rm -f /etc/ssh/sshd_config.d/99-harden.conf
        log "  sshd 설정 검사 실패. 변경을 되돌림"
    fi
else
    log "  건드리지 않음"
fi

echo
log "완료. 아래는 참고용 현황"
log "쓰지 않으면 중지를 검토할 서비스:"
for s in xrdp rpcbind cups; do
    printf '  %-10s %s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null || echo inactive)"
done
log "방화벽으로 외부 접근은 이미 막혔으므로 중지는 선택 사항"
