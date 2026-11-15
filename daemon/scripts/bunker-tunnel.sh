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
# Device binding is persistent: Once you pair a device, the session key and ntfy
# channel are saved. Running `zed-tunnel` connects immediately without asking to
# scan a QR code every time. Run `zed-tunnel --bind` to display the pairing QR code.
# ==============================================================================

set -euo pipefail

# ANSI styling
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
NC="\033[0m"

CONFIG_DIR="${HOME}/.config/zed-remote"
CONFIG_FILE="${CONFIG_DIR}/bunker-session.json"
LOG_FILE="/tmp/zed-pinggy.log"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SYSTEMD_USER_DIR}/zed-tunnel.service"

mkdir -p "${CONFIG_DIR}"

show_help() {
    echo -e "${BOLD}Zed Remote Bunker Tunnel (Fortinet/DPI Bypass)${NC}"
    echo -e "${CYAN}Secure AES-256-GCM encrypted reverse tunnel over SSH port 443.${NC}\n"
    echo -e "${BOLD}USAGE:${NC}"
    echo -e "  zed-tunnel [OPTIONS] [PORT]\n"
    echo -e "${BOLD}COMMANDS & FLAGS:${NC}"
    echo -e "  ${GREEN}(no args)${NC}         Start encrypted tunnel with saved device binding (silent, no QR)"
    echo -e "  ${GREEN}-b, --bind${NC}        Show pairing QR code to bind a new mobile device"
    echo -e "  ${GREEN}--reset${NC}           Generate brand new encryption keys and ntfy channel"
    echo -e "  ${GREEN}-s, --status${NC}      Show tunnel connection and systemd service status"
    echo -e "  ${GREEN}--stop${NC}            Stop running background tunnel process"
    echo -e "  ${GREEN}--service <CMD>${NC}   Manage systemd user service: status | start | stop | restart | enable | disable"
    echo -e "  ${GREEN}-i, --inject${NC}      Inject daemon into official Zed settings.json"
    echo -e "  ${GREEN}-u, --update${NC}      Update Zed Remote and all host tools to the latest version"
    echo -e "  ${GREEN}-h, --help${NC}        Show this help message\n"
    echo -e "${BOLD}ARGUMENTS:${NC}"
    echo -e "  PORT               Local Zed daemon gateway port (default: 8443)\n"
    echo -e "${BOLD}SHORTHAND ALIAS:${NC}"
    echo -e "  You can use ${CYAN}zedt${NC} as a direct shorthand for ${CYAN}zed-tunnel${NC}.\n"
    echo -e "${BOLD}PERSISTENT BINDING WORKFLOW:${NC}"
    echo -e "  1. First time setup:"
    echo -e "       ${CYAN}zed-tunnel --bind${NC}"
    echo -e "     Scan the QR code once with your phone in the Zed Remote mobile app."
    echo -e "     Your device binding (channel & AES-GCM key) is permanently saved.\n"
    echo -e "  2. Everyday use:"
    echo -e "       ${CYAN}zed-tunnel${NC}"
    echo -e "     Starts the tunnel immediately. Your phone receives dynamic updates"
    echo -e "     automatically without having to scan a QR code again!\n"
    echo -e "  3. Automatic background startup (Systemd):"
    echo -e "       ${CYAN}zed-tunnel --service enable${NC}"
    echo -e "     Starts the tunnel automatically on every system boot.\n"
    echo -e "${BOLD}UPDATE INSTRUCTIONS:${NC}"
    echo -e "  To update Zed Remote to the latest release at any time:"
    echo -e "    ${CYAN}zed-tunnel --update${NC}"
    echo -e "  Or run the one-line installer:"
    echo -e "    ${CYAN}curl -fsSL https://raw.githubusercontent.com/seeramsujay/remote-zed/main/install.sh | bash${NC}\n"
    exit 0
}

manage_service() {
    local cmd="${1:-status}"
    case "$cmd" in
        enable)
            mkdir -p "${SYSTEMD_USER_DIR}"
            cat << EOF > "${SERVICE_FILE}"
[Unit]
Description=Zed Remote Bunker Tunnel Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${HOME}/.local/bin/zed-tunnel --daemon
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
            systemctl --user daemon-reload
            systemctl --user enable --now zed-tunnel.service
            echo -e "${GREEN}[✓] zed-tunnel systemd user service enabled and started!${NC}"
            echo -e "    Check status: ${CYAN}systemctl --user status zed-tunnel${NC}"
            echo -e "    Live logs:    ${CYAN}journalctl --user -u zed-tunnel -f${NC}"
            ;;
        disable)
            systemctl --user stop zed-tunnel.service || true
            systemctl --user disable zed-tunnel.service || true
            rm -f "${SERVICE_FILE}"
            systemctl --user daemon-reload
            echo -e "${YELLOW}[✓] zed-tunnel systemd service disabled and stopped.${NC}"
            ;;
        start|stop|restart|status)
            systemctl --user "$cmd" zed-tunnel.service
            ;;
        *)
            echo -e "${RED}[!] Unknown service command: $cmd${NC}"
            echo -e "    Available: enable, disable, start, stop, restart, status"
            exit 1
            ;;
    esac
    exit 0
}

show_status() {
    echo -e "${BOLD}Zed Remote Status:${NC}"
    echo -e "--------------------------------------------------"
    if pgrep -f "free.pinggy.io" >/dev/null 2>&1; then
        echo -e "Tunnel Process:  ${GREEN}RUNNING${NC}"
        if [[ -f "${LOG_FILE}" ]]; then
            CURRENT_URL=$(grep -oE "(tcp|http|https)://[a-zA-Z0-9.-]+:[0-9]+" "${LOG_FILE}" | tail -n 1 || true)
            if [[ -n "${CURRENT_URL}" ]]; then
                echo -e "Active Endpoint: ${CYAN}${CURRENT_URL}${NC}"
            fi
        fi
    else
        echo -e "Tunnel Process:  ${YELLOW}STOPPED${NC}"
    fi

    if [[ -f "${CONFIG_FILE}" ]]; then
        SAVED_TOPIC=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}'))['ntfy_topic'])" 2>/dev/null || echo "corrupt")
        echo -e "Saved Binding:   ${GREEN}CONFIGURED${NC} (${SAVED_TOPIC})"
    else
        echo -e "Saved Binding:   ${YELLOW}NOT CONFIGURED${NC} (Run: zed-tunnel --bind)"
    fi

    if systemctl --user is-active zed-tunnel.service >/dev/null 2>&1; then
        echo -e "Systemd Service: ${GREEN}ACTIVE${NC}"
    elif systemctl --user is-enabled zed-tunnel.service >/dev/null 2>&1; then
        echo -e "Systemd Service: ${YELLOW}ENABLED (INACTIVE)${NC}"
    else
        echo -e "Systemd Service: ${YELLOW}DISABLED (On-Demand Mode)${NC}"
    fi
    echo -e "--------------------------------------------------"
    exit 0
}

stop_tunnel() {
    echo -e "${YELLOW}[*] Stopping running tunnel instances...${NC}"
    pkill -f "free.pinggy.io" || true
    if systemctl --user is-active zed-tunnel.service >/dev/null 2>&1; then
        systemctl --user stop zed-tunnel.service
        echo -e "${GREEN}[✓] Stopped systemd service.${NC}"
    fi
    echo -e "${GREEN}[✓] Tunnel stopped.${NC}"
    exit 0
}

run_update() {
    echo -e "${BLUE}${BOLD}[*] Updating Zed Remote to the latest version...${NC}"
    INSTALL_DIR="${HOME}/.local/share/zed-remote"
    if [[ -d "${INSTALL_DIR}/.git" ]] && command -v git &>/dev/null; then
        cd "${INSTALL_DIR}"
        git fetch origin
        git reset --hard origin/main
        chmod +x tools/*.sh
        ln -sf "${INSTALL_DIR}/tools/bunker-tunnel.sh" "${HOME}/.local/bin/zed-tunnel"
        ln -sf "${INSTALL_DIR}/tools/inject-daemon.sh" "${HOME}/.local/bin/zed-inject"
        echo -e "${GREEN}[✓] Successfully updated Zed Remote via git!${NC}"
    else
        curl -fsSL https://raw.githubusercontent.com/seeramsujay/remote-zed/main/install.sh | bash
    fi
    exit 0
}

# Parse Command-Line Options
SHOW_BIND_QR=false
RESET_KEYS=false
DAEMON_MODE=false
LOCAL_PORT="8443"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -b|--bind)
            SHOW_BIND_QR=true
            shift
            ;;
        --reset)
            RESET_KEYS=true
            SHOW_BIND_QR=true
            shift
            ;;
        -s|--status)
            show_status
            ;;
        --stop)
            stop_tunnel
            ;;
        --service)
            manage_service "${2:-status}"
            shift 2 || shift
            ;;
        -i|--inject)
            INJECT_SCRIPT=""
            CANDIDATES=(
                "$(dirname "$0")/inject-daemon.sh"
                "${HOME}/.local/share/zed-remote/tools/inject-daemon.sh"
                "${HOME}/.local/bin/zed-inject"
            )
            for cand in "${CANDIDATES[@]}"; do
                if [[ -f "$cand" ]]; then
                    INJECT_SCRIPT="$cand"
                    break
                fi
            done
            if [[ -n "$INJECT_SCRIPT" ]]; then
                echo -e "${BLUE}[*] Injecting Zed Remote daemon into Zed settings...${NC}"
                bash "$INJECT_SCRIPT"
            else
                echo -e "${RED}[!] inject-daemon.sh not found.${NC}"
                exit 1
            fi
            exit 0
            ;;
        -u|--update)
            run_update
            ;;
        --daemon)
            DAEMON_MODE=true
            shift
            ;;
        -p|--port)
            LOCAL_PORT="$2"
            shift 2
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                LOCAL_PORT="$1"
                shift
            else
                echo -e "${RED}[!] Unknown option: $1${NC}"
                echo -e "    Use ${CYAN}zed-tunnel --help${NC} for usage."
                exit 1
            fi
            ;;
    esac
done

if [[ "$DAEMON_MODE" = false ]]; then
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
  ______        _   ____                      _       
 |__  /  ___ __| | |  _ \ ___ _ __ ___   ___ | |_ ___ 
   / /  / _ \ _` | | |_) / _ \ '_ ` _ \ / _ \| __/ _ \
  / /__|  __/ (_| | |  _ <  __/ | | | | | (_) | ||  __/
 /_____\___|\__,_| |_| \_\___|_| |_| |_|\___/ \__\___|
EOF
    echo -e "${NC}"
    echo -e "${BOLD}🛡️  Zed Remote Bunker Tunnel (Fortinet / Firewall Bypass) 🛡️${NC}"
    echo -e "======================================================================\n"
fi

# Load or generate persistent session keys
if [[ -f "${CONFIG_FILE}" ]] && [[ "$RESET_KEYS" = false ]]; then
    TOPIC=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}'))['ntfy_topic'])")
    KEY_B64=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}'))['key'])")
    TOKEN=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}'))['token'])")
    if [[ "$DAEMON_MODE" = false ]]; then
        echo -e "${GREEN}[✓] Loaded persistent device binding:${NC}"
        echo -e "    Channel Topic: ${CYAN}${TOPIC}${NC}"
        echo -e "    Target Port:   ${CYAN}${LOCAL_PORT}${NC}"
        echo -e "    AES-256 Key:   ${CYAN}[REDACTED]${NC}\n"
    fi
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
    SHOW_BIND_QR=true
    if [[ "$DAEMON_MODE" = false ]]; then
        echo -e "${GREEN}[+] Generated persistent session keys -> ${CONFIG_FILE}${NC}\n"
    fi
fi

# Render pairing payload and Terminal QR Code if binding
if [[ "$SHOW_BIND_QR" = true ]] && [[ "$DAEMON_MODE" = false ]]; then
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

    echo -e "${YELLOW}${BOLD}📱 SCAN THIS QR CODE IN ZED REMOTE APP (ONE-TIME PAIRING):${NC}"
    echo "----------------------------------------------------------------------"
    python3 -c "
import qrcode
qr = qrcode.QRCode(border=1)
qr.add_data('${QR_PAYLOAD}')
qr.make(fit=True)
qr.print_ascii(invert=True)
" 2>/dev/null || echo -e "Install 'qrcode' for ASCII QR rendering: pip install qrcode"
    echo "----------------------------------------------------------------------"
    echo -e "Pairing Payload: ${CYAN}${QR_PAYLOAD}${NC}"
    echo -e "${GREEN}[✓] Device paired! Future runs of 'zed-tunnel' will not require scanning again.${NC}"
    echo "----------------------------------------------------------------------"
    echo ""
fi

cleanup() {
    echo ""
    echo -e "${YELLOW}[*] Shutting down pinggy tunnel...${NC}"
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
            print('[+] Published encrypted dynamic rendezvous endpoint to ntfy.sh')
except Exception as e:
    print(f'[-] Failed to publish to ntfy: {e}')
"
}

# Main tunnel loop (Pinggy sessions refresh automatically every 55 minutes on free tier)
while true; do
    echo -e "${BLUE}[*] Initializing fresh reverse tunnel via SSH (port 443)...${NC}"
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
        echo -e "${GREEN}${BOLD}[+] Tunnel is LIVE: ${TUNNEL_URL}${NC}"
        encrypt_and_publish "${TUNNEL_URL}"
    else
        echo -e "${YELLOW}[-] Tunnel address pending or error. Log contents:${NC}"
        head -n 10 "${LOG_FILE}"
    fi

    echo -e "${BLUE}[*] Tunnel active. Automatic refresh in 55 minutes...${NC}"
    sleep 3300
done
