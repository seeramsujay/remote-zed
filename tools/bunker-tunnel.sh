#!/usr/bin/env bash
# ==============================================================================
# Zed Remote Bunker Tunnel & Rendezvous Server
# ==============================================================================
# Fortinet and enterprise campus firewalls routinely block Tailscale and WireGuard
# (UDP port 41641 / WireGuard protocol DPI).
#
# This script creates an unblockable reverse tunnel via SSH over port 443
# (indistinguishable from standard TLS traffic) to Pinggy, dynamically publishes
# the endpoint to an ephemeral, high-entropy (48+ hex char) ntfy.sh topic,
# and encrypts the payload end-to-end with AES-256-GCM.
#
# Eavesdroppers on the network or on ntfy cannot observe the tunnel destination.
# ==============================================================================

set -euo pipefail

LOCAL_PORT="${1:-8443}"
CONFIG_DIR="${HOME}/.config/zed-remote"
CONFIG_FILE="${CONFIG_DIR}/bunker-session.json"
LOG_FILE="/tmp/zed-pinggy.log"

mkdir -p "${CONFIG_DIR}"

echo "======================================================================"
echo "          🛡️  ZED REMOTE BUNKER TUNNEL (FORTINET BYPASS) 🛡️           "
echo "======================================================================"

# Generate or load ephemeral session keys
if [[ -f "${CONFIG_FILE}" ]]; then
    TOPIC=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}'))['ntfy_topic'])")
    KEY_B64=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}'))['key'])")
    TOKEN=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}'))['token'])")
    echo "[*] Loaded existing bunker session credentials from ${CONFIG_FILE}"
else
    # Cryptographically random topic (48 hex chars = 192 bits of entropy)
    TOPIC="zed-bunker-$(openssl rand -hex 24)"
    # 256-bit AES-GCM symmetric key
    KEY_B64=$(openssl rand 32 | base64 -w 0)
    # Auth bearer token
    TOKEN=$(openssl rand -hex 24)

    cat <<EOF > "${CONFIG_FILE}"
{
  "ntfy_topic": "${TOPIC}",
  "key": "${KEY_B64}",
  "token": "${TOKEN}",
  "port": ${LOCAL_PORT}
}
EOF
    chmod 600 "${CONFIG_FILE}"
    echo "[+] Generated fresh session keys and persisted to ${CONFIG_FILE}"
fi

# Render pairing payload and Terminal QR Code
QR_PAYLOAD=$(python3 -c "
import json, base64

data = {
    'version': 'bunker-v2',
    'ntfy_topic': '${TOPIC}',
    'key': '${KEY_B64}',
    'token': '${TOKEN}',
    'port': ${LOCAL_PORT}
}
encoded = base64.urlsafe_b64encode(json.dumps(data).encode()).decode().rstrip('=')
print('ZEDBUNKER:' + encoded)
")

echo ""
echo "📱 SCAN THIS QR CODE IN ZED REMOTE ANDROID APP:"
echo "----------------------------------------------------------------------"
python3 -c "
import qrcode
qr = qrcode.QRCode(border=1)
qr.add_data('${QR_PAYLOAD}')
qr.make(fit=True)
qr.print_ascii(invert=True)
"
echo "----------------------------------------------------------------------"
echo "Topic: ${TOPIC}"
echo "Key:   [REDACTED AES-256-GCM KEY]"
echo "Token: ${TOKEN}"
echo "Local Gateway Port: ${LOCAL_PORT}"
echo "----------------------------------------------------------------------"
echo ""

cleanup() {
    echo ""
    echo "[*] Shutting down pinggy tunnel..."
    pkill -f "free.pinggy.io" || true
    exit 0
}
trap cleanup SIGINT SIGTERM

encrypt_and_publish() {
    local target_url="$1"
    python3 -c "
import base64, os, urllib.request
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

key = base64.b64decode('${KEY_B64}')
aesgcm = AESGCM(key)
nonce = os.urandom(12)
plaintext = '${target_url}'.encode('utf-8')
ciphertext = aesgcm.encrypt(nonce, plaintext, None)
payload_b64 = base64.b64encode(nonce + ciphertext).decode('utf-8')

req = urllib.request.Request(
    'https://ntfy.sh/${TOPIC}',
    data=payload_b64.encode('utf-8'),
    headers={
        'Title': 'Bunker Tunnel Active',
        'Priority': 'high',
        'Tags': 'shield,lock'
    }
)
try:
    with urllib.request.urlopen(req) as response:
        if response.status == 200:
            print('[+] Published encrypted dynamic endpoint to ntfy.sh')
except Exception as e:
    print(f'[-] Failed to publish to ntfy: {e}')
"
}

# Main tunnel loop (Pinggy sessions expire every 55 minutes on free tier)
while true; do
    echo "[*] Initializing fresh tunnel via SSH (port 443)..."
    pkill -f "free.pinggy.io" || true
    > "${LOG_FILE}"

    stdbuf -oL ssh -p 443 -R0:localhost:"${LOCAL_PORT}" tcp@free.pinggy.io \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 > "${LOG_FILE}" 2>&1 &
    SSH_PID=$!

    # Wait for handshake
    sleep 5

    # Extract dynamic URL
    TUNNEL_URL=$(grep -oE "(tcp|http|https)://[a-zA-Z0-9.-]+:[0-9]+" "${LOG_FILE}" | head -n 1 || true)

    if [[ -n "${TUNNEL_URL}" ]]; then
        echo "[+] Tunnel is LIVE: ${TUNNEL_URL}"
        encrypt_and_publish "${TUNNEL_URL}"
    else
        echo "[-] Tunnel address pending or error. Log contents:"
        head -n 10 "${LOG_FILE}"
    fi

    echo "[*] Tunnel active. Next automatic refresh in 55 minutes..."
    sleep 3300
done
