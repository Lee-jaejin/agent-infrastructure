#!/bin/bash
# Join this Linux node to the OpenClaw VPN network.
#
# Prerequisites (control tower):
#   1. yarn start
#   2. ./scripts/serve-ca.sh  (in a separate terminal, to serve CA cert)
#
# Usage:
#   ./scripts/node-join.sh <control-tower-ip> <api-key>
#
# Example:
#   ./scripts/node-join.sh 192.168.1.10 hskey-api-xxxx

set -euo pipefail

CONTROL_IP="${1:?Usage: node-join.sh <control-tower-ip> <api-key>}"
API_KEY="${2:?Usage: node-join.sh <control-tower-ip> <api-key>}"
HEADSCALE_URL="https://${CONTROL_IP}:8080"
CA_URL="http://${CONTROL_IP}:8880/ca.crt"
# headscale v0.28 부터 preauthkey API 가 사용자를 이름이 아닌 숫자 ID 로 받음
# ID 확인: podman exec headscale headscale users list
HEADSCALE_USER_ID="${HEADSCALE_USER_ID:-1}"

# preauthkey API 는 상대 시간("1h")이 아니라 RFC3339 시각을 요구
# 리눅스는 GNU date, macOS 는 BSD date 라 문법이 달라서 순서대로 시도
EXPIRATION=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)

echo "=== Joining OpenClaw network ==="
echo "Control tower: ${HEADSCALE_URL}"

# 1. Install CA certificate
echo "[1/3] Installing CA certificate..."
if curl -sf --max-time 5 "${CA_URL}" -o /tmp/headscale-ca.crt; then
    sudo cp /tmp/headscale-ca.crt /usr/local/share/ca-certificates/headscale-ca.crt
    sudo update-ca-certificates --fresh > /dev/null 2>&1
    echo "  CA certificate installed."
else
    echo "  Warning: could not download CA cert from ${CA_URL}"
    echo "  Run './scripts/serve-ca.sh' on the control tower first, or install manually."
    echo "  Continuing — if already installed this is fine."
fi

# 2. Create preauthkey via headscale API
echo "[2/3] Generating auth key..."
AUTHKEY=$(curl -sf \
    --cacert /usr/local/share/ca-certificates/headscale-ca.crt \
    -X POST "${HEADSCALE_URL}/api/v1/preauthkey" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"user\":\"${HEADSCALE_USER_ID}\",\"reusable\":false,\"ephemeral\":false,\"expiration\":\"${EXPIRATION}\"}" \
    | jq -r '.preAuthKey.key' 2>/dev/null || true)

# Fallback to -k if CA cert not yet trusted by curl
if [[ -z "${AUTHKEY}" || "${AUTHKEY}" == "null" ]]; then
    AUTHKEY=$(curl -sf -k \
        -X POST "${HEADSCALE_URL}/api/v1/preauthkey" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"user\":\"${HEADSCALE_USER_ID}\",\"reusable\":false,\"ephemeral\":false,\"expiration\":\"${EXPIRATION}\"}" \
        | jq -r '.preAuthKey.key')
fi

if [[ -z "${AUTHKEY}" || "${AUTHKEY}" == "null" ]]; then
    echo "Error: failed to generate auth key. Check IP and API key." >&2
    exit 1
fi

# 3. Connect to VPN
echo "[3/3] Connecting to VPN..."
sudo tailscale up \
    --login-server="${HEADSCALE_URL}" \
    --authkey="${AUTHKEY}" \
    --accept-routes

echo ""
echo "Done. Run 'tailscale status' to verify."
