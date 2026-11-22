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
WHITE="\033[1;37m"
NC="\033[0m"

CONFIG_DIR="${HOME}/.config/zed-remote"
CONFIG_FILE="${CONFIG_DIR}/bunker-session.json"
PID_FILE="${CONFIG_DIR}/zed-tunnel.pid"
LOCK_FILE="${CONFIG_DIR}/zed-tunnel.lock"
LOG_FILE="${CONFIG_DIR}/zed-pinggy.log"
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
    if ! command -v systemctl &>/dev/null; then
        echo -e "${RED}[!] systemctl is not available on this platform (macOS / non-systemd).${NC}"
        echo -e "    Use on-demand mode: ${CYAN}zed-tunnel${NC} (or ${CYAN}zedt${NC})"
        exit 1
    fi
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
    local is_running=false
    if [[ -f "${PID_FILE}" ]]; then
        local spid
        spid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [[ -n "${spid}" ]] && kill -0 "${spid}" 2>/dev/null; then
            local cmdline=""
            if [[ -r "/proc/${spid}/cmdline" ]]; then
                cmdline=$(tr '\0' ' ' < "/proc/${spid}/cmdline" 2>/dev/null || true)
            fi
            if [[ -z "$cmdline" ]]; then
                cmdline=$(ps -p "${spid}" -o command= 2>/dev/null || true)
            fi
            if [[ "$cmdline" == *"zed-tunnel"* ]] || [[ "$cmdline" == *"bunker-tunnel"* ]] || [[ "$cmdline" == *"zedt"* ]]; then
                is_running=true
            fi
        fi
    fi
    if ! $is_running && pgrep -f "tcp@.*pinggy\.io" >/dev/null 2>&1; then
        is_running=true
    fi

    if $is_running; then
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

    if command -v systemctl &>/dev/null; then
        if systemctl --user is-active zed-tunnel.service >/dev/null 2>&1; then
            echo -e "Systemd Service: ${GREEN}ACTIVE${NC}"
        elif systemctl --user is-enabled zed-tunnel.service >/dev/null 2>&1; then
            echo -e "Systemd Service: ${YELLOW}ENABLED (INACTIVE)${NC}"
        else
            echo -e "Systemd Service: ${YELLOW}DISABLED (On-Demand Mode)${NC}"
        fi
    else
        echo -e "Systemd Service: ${YELLOW}NOT AVAILABLE (macOS / non-systemd)${NC}"
    fi
    echo -e "--------------------------------------------------"
    exit 0
}

stop_tunnel() {
    echo -e "${YELLOW}[*] Stopping running tunnel instances...${NC}"
    if [[ -f "${PID_FILE}" ]]; then
        local spid
        spid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [[ -n "${spid}" ]] && kill -0 "${spid}" 2>/dev/null; then
            local cmdline=""
            if [[ -r "/proc/${spid}/cmdline" ]]; then
                cmdline=$(tr '\0' ' ' < "/proc/${spid}/cmdline" 2>/dev/null || true)
            fi
            if [[ -z "$cmdline" ]]; then
                cmdline=$(ps -p "${spid}" -o command= 2>/dev/null || true)
            fi
            if [[ "$cmdline" == *"zed-tunnel"* ]] || [[ "$cmdline" == *"bunker-tunnel"* ]] || [[ "$cmdline" == *"zedt"* ]]; then
                kill "${spid}" 2>/dev/null || true
                for _ in {1..10}; do
                    if ! kill -0 "${spid}" 2>/dev/null; then
                        break
                    fi
                    sleep 0.1
                done
                if kill -0 "${spid}" 2>/dev/null; then
                    kill -9 "${spid}" 2>/dev/null || true
                fi
            else
                echo -e "${YELLOW}[!] Stale PID ${spid} does not match zed-tunnel supervisor, cleaning PID file.${NC}"
            fi
        fi
        rm -f "${PID_FILE}"
    fi
    pkill -f "tcp@.*pinggy\.io" 2>/dev/null || true
    if command -v systemctl &>/dev/null && systemctl --user is-active zed-tunnel.service >/dev/null 2>&1; then
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
        -h|--help|help)
            show_help
            ;;
        -b|--bind|bind|qr|pair)
            SHOW_BIND_QR=true
            shift
            ;;
        --reset|reset)
            RESET_KEYS=true
            SHOW_BIND_QR=true
            shift
            ;;
        -s|--status|status)
            show_status
            ;;
        --stop|stop)
            stop_tunnel
            ;;
        --service|service)
            manage_service "${2:-status}"
            ;;
        -i|--inject|inject)
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
        -u|--update|update)
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

render_bind_qr() {
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

    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "${LOCAL_IP}" ]]; then
        LOCAL_IP="127.0.0.1"
    fi
    WEB_BRIDGE_URL="http://${LOCAL_IP}:${LOCAL_PORT}/?token=${TOKEN}"

    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${YELLOW}${BOLD}🚀 DUAL-ENGINE ACCESS: NATIVE APP OR OPENCODE WEB PWA${NC}"
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${WHITE}${BOLD}[METHOD 1 - Primary] Native Android Companion App${NC}"
    echo -e "📱 Scan this QR code in the Remote Zed Android App (one-time pairing):"
    echo "----------------------------------------------------------------------"
    python3 -c "
import qrcode
qr = qrcode.QRCode(border=1)
qr.add_data('${QR_PAYLOAD}')
qr.make(fit=True)
qr.print_ascii(invert=True)
" 2>/dev/null || echo -e "Install 'qrcode' for ASCII QR rendering: pip install qrcode"
    echo "----------------------------------------------------------------------"
    echo -e "Native App Pairing Payload: ${CYAN}${QR_PAYLOAD}${NC}"
    echo ""
    echo -e "${WHITE}${BOLD}[METHOD 2 - Fallback] OpenCode Mobile Web Bridge (PWA)${NC}"
    echo -e "🌐 Open in ANY browser on your phone or install as a PWA (Zero-Config):"
    echo -e "   URL: ${GREEN}${BOLD}${WEB_BRIDGE_URL}${NC}"
    echo "----------------------------------------------------------------------"
    python3 -c "
import qrcode
qr = qrcode.QRCode(border=1)
qr.add_data('${WEB_BRIDGE_URL}')
qr.make(fit=True)
qr.print_ascii(invert=True)
" 2>/dev/null || true
    echo "----------------------------------------------------------------------"
    echo -e "${GREEN}[✓] Dual-engine active! Use native app or Web PWA as fallback anytime.${NC}"
    echo -e "${CYAN}${BOLD}======================================================================${NC}\n"
}

acquire_lock() {
    if command -v flock &>/dev/null; then
        flock -n 200
    else
        python3 -c "
import fcntl, sys
try:
    fcntl.flock(200, fcntl.LOCK_EX | fcntl.LOCK_NB)
except (BlockingIOError, OSError):
    sys.exit(1)
"
    fi
}

release_lock() {
    if command -v flock &>/dev/null; then
        flock -u 200 2>/dev/null || true
    else
        python3 -c "import fcntl; fcntl.flock(200, fcntl.LOCK_UN)" 2>/dev/null || true
    fi
    exec 200>&- 2>/dev/null || true
}

HAS_LOCK=false
CLEANING_UP=false

cleanup() {
    # Prevent re-entrant cleanup calls (e.g., SIGINT followed by EXIT trap)
    if [[ "$CLEANING_UP" = true ]]; then
        return
    fi
    CLEANING_UP=true
    trap - SIGINT SIGTERM EXIT

    echo ""
    echo -e "${YELLOW}[*] Shutting down pinggy tunnel...${NC}"
    if [[ -n "${SSH_PID:-}" ]] && kill -0 "${SSH_PID}" 2>/dev/null; then
        kill "${SSH_PID}" 2>/dev/null || true
        for _ in {1..10}; do
            if ! kill -0 "${SSH_PID}" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 "${SSH_PID}" 2>/dev/null; then
            kill -9 "${SSH_PID}" 2>/dev/null || true
        fi
        wait "${SSH_PID}" 2>/dev/null || true
    fi
    pkill -f "tcp@.*pinggy\.io" 2>/dev/null || true
    if [[ "$HAS_LOCK" = true ]]; then
        rm -f "${PID_FILE}"
        release_lock
    fi
    exit 0
}

# Temporary trap before acquiring lock to avoid spurious cleanup on premature abort
trap 'exit 130' SIGINT SIGTERM

# Acquire exclusive lock BEFORE credential mutation (--reset) or supervisor startup
exec 200>"${LOCK_FILE}"
if ! acquire_lock; then
    if [[ "$SHOW_BIND_QR" = true ]] && [[ "$RESET_KEYS" = false ]] && [[ -f "${CONFIG_FILE}" ]]; then
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
        TOPIC=$(python3 -c "import json; d = json.load(open('${CONFIG_FILE}')); print(d.get('ntfy_topic', ''))")
        KEY_B64=$(python3 -c "import json; d = json.load(open('${CONFIG_FILE}')); print(d.get('key') or d.get('bunker_key', ''))")
        TOKEN=$(python3 -c "import json; d = json.load(open('${CONFIG_FILE}')); print(d.get('token') or d.get('daemon_token', ''))")
        echo -e "${GREEN}[✓] Loaded persistent device binding:${NC}"
        echo -e "    Channel Topic: ${CYAN}${TOPIC}${NC}"
        echo -e "    Target Port:   ${CYAN}${LOCAL_PORT}${NC}"
        echo -e "    AES-256 Key:   ${CYAN}[REDACTED]${NC}\n"
        render_bind_qr
        echo -e "${GREEN}[✓] Tunnel is actively running in the background.${NC}"
        echo -e "    Check status with: ${CYAN}zed-tunnel -s${NC}"
        exit 0
    fi
    echo -e "${RED}[!] Another zed-tunnel supervisor is already running.${NC}"
    echo -e "${YELLOW}[*] Check status with: zed-tunnel -s"
    echo -e "    To stop or reset:  zed-tunnel --stop${NC}"
    exit 1
fi
HAS_LOCK=true
echo $$ > "${PID_FILE}"
trap cleanup SIGINT SIGTERM EXIT

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
    TOPIC=$(python3 -c "import json; d = json.load(open('${CONFIG_FILE}')); print(d.get('ntfy_topic', ''))")
    KEY_B64=$(python3 -c "import json; d = json.load(open('${CONFIG_FILE}')); print(d.get('key') or d.get('bunker_key', ''))")
    TOKEN=$(python3 -c "import json; d = json.load(open('${CONFIG_FILE}')); print(d.get('token') or d.get('daemon_token', ''))")
    if [[ "$DAEMON_MODE" = false ]]; then
        echo -e "${GREEN}[✓] Loaded persistent device binding:${NC}"
        echo -e "    Channel Topic: ${CYAN}${TOPIC}${NC}"
        echo -e "    Target Port:   ${CYAN}${LOCAL_PORT}${NC}"
        echo -e "    AES-256 Key:   ${CYAN}[REDACTED]${NC}\n"

        # Check if the active daemon running on the port is an outdated instance
        if command -v curl &>/dev/null; then
            CHECK_RESP=$(curl -s --connect-timeout 1 -m 2 -H "Authorization: Bearer ${TOKEN}" "http://127.0.0.1:${LOCAL_PORT}/v2/projects/default/threads" 2>/dev/null || echo "")
            if echo "$CHECK_RESP" | grep -q "thread-1794814517197"; then
                echo -e "${YELLOW}[!] WARNING: An outdated daemon (v0.1.2) is still held in memory by Zed Editor.${NC}"
                echo -e "${YELLOW}[!] Please close and reopen Zed Editor on your laptop to load the updated daemon!${NC}\n"
            fi
        fi
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
    render_bind_qr
fi

encrypt_and_publish() {
    local target_url="$1"
    python3 -c "
import base64, os, urllib.request, subprocess, shutil
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

key = base64.b64decode('${KEY_B64}')
aesgcm = AESGCM(key)
nonce = os.urandom(12)
plaintext = '${target_url}'.encode('utf-8')
ciphertext = aesgcm.encrypt(nonce, plaintext, None)
payload_b64 = base64.b64encode(nonce + ciphertext).decode('utf-8')

# Publish to high-availability rendezvous federation
servers = ['https://ntfy.sh', 'https://ntfy.adminforge.de']
published = False
hit_rate_limit = False

for srv in servers:
    req = urllib.request.Request(
        f'{srv}/${TOPIC}',
        data=payload_b64.encode('utf-8'),
        headers={
            'Title': 'Bunker Tunnel Active',
            'Priority': 'high',
            'Tags': 'shield,lock',
            'Cache': 'yes'
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status == 200:
                print(f'[+] Published encrypted dynamic rendezvous endpoint to {srv}')
                published = True
    except Exception as e:
        if '429' in str(e):
            hit_rate_limit = True
        print(f'[-] Rendezvous notice ({srv}): {e}')

# If official ntfy.sh is rate-limited on this IP, dispatch via GitHub Actions cloud relay
if hit_rate_limit and shutil.which('gh'):
    try:
        subprocess.run(
            ['gh', 'workflow', 'run', 'bunker-relay.yml', '-f', f'topic=${TOPIC}', '-f', f'payload={payload_b64}'],
            capture_output=True,
            timeout=5
        )
        print('[+] Dispatched cloud rendezvous relay via GitHub Actions')
    except Exception:
        pass
"
}

# Candidate Pinggy regional clusters for automatic failover
CANDIDATE_HOSTS=("ap.a.pinggy.io" "us.a.pinggy.io" "eu.a.pinggy.io" "a.pinggy.io" "free.pinggy.io")
HOST_INDEX=0

# Main tunnel loop (Pinggy sessions refresh automatically every 55 minutes on free tier)
while true; do
    PINGGY_HOST="${CANDIDATE_HOSTS[$HOST_INDEX]}"
    echo -e "${BLUE}[*] Initializing fresh reverse tunnel via SSH to ${PINGGY_HOST} (port 443)...${NC}"
    if [[ -n "${SSH_PID:-}" ]] && kill -0 "${SSH_PID}" 2>/dev/null; then
        kill "${SSH_PID}" 2>/dev/null || true
        for _ in {1..10}; do
            if ! kill -0 "${SSH_PID}" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 "${SSH_PID}" 2>/dev/null; then
            kill -9 "${SSH_PID}" 2>/dev/null || true
        fi
        wait "${SSH_PID}" 2>/dev/null || true
    fi
    : > "${LOG_FILE}"

    SSH_CMD=(ssh -p 443 -R0:localhost:"${LOCAL_PORT}" -T tcp@"${PINGGY_HOST}" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=8 \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3)
    if command -v stdbuf &>/dev/null; then
        stdbuf -oL "${SSH_CMD[@]}" > "${LOG_FILE}" 2>&1 200>&- &
    elif command -v gstdbuf &>/dev/null; then
        gstdbuf -oL "${SSH_CMD[@]}" > "${LOG_FILE}" 2>&1 200>&- &
    else
        "${SSH_CMD[@]}" > "${LOG_FILE}" 2>&1 200>&- &
    fi
    SSH_PID=$!

    # Wait for handshake (poll up to 8 seconds)
    TUNNEL_URL=""
    for _ in {1..8}; do
        sleep 1
        TUNNEL_URL=$(grep -oE "(tcp|http|https)://[a-zA-Z0-9.-]+:[0-9]+" "${LOG_FILE}" | head -n 1 || true)
        if [[ -n "${TUNNEL_URL}" ]]; then
            break
        fi
        if ! kill -0 "${SSH_PID}" 2>/dev/null; then
            break
        fi
    done

    if [[ -n "${TUNNEL_URL}" ]]; then
        echo -e "${GREEN}${BOLD}[+] Tunnel is LIVE: ${TUNNEL_URL}${NC}"
        encrypt_and_publish "${TUNNEL_URL}"
    else
        echo -e "${YELLOW}[-] Tunnel address pending or error on ${PINGGY_HOST}. Log contents:${NC}"
        head -n 10 "${LOG_FILE}"
        # Rotate candidate host on failure
        HOST_INDEX=$(( (HOST_INDEX + 1) % ${#CANDIDATE_HOSTS[@]} ))
    fi

    COUNT=0
    while kill -0 "${SSH_PID}" 2>/dev/null; do
        if [[ -z "${TUNNEL_URL}" ]]; then
            TUNNEL_URL=$(grep -oE "(tcp|http|https)://[a-zA-Z0-9.-]+:[0-9]+" "${LOG_FILE}" | head -n 1 || true)
            if [[ -n "${TUNNEL_URL}" ]]; then
                echo -e "${GREEN}${BOLD}[+] Tunnel is LIVE: ${TUNNEL_URL}${NC}"
                encrypt_and_publish "${TUNNEL_URL}"
            fi
        fi
        sleep 5
        COUNT=$((COUNT + 5))
        # Enforce refresh at 55 minutes for Pinggy free tier rotation
        if [[ ${COUNT} -ge 3300 ]]; then
            echo -e "${BLUE}[*] 55-minute rotation window reached, rotating tunnel...${NC}"
            break
        fi
    done

    echo -e "${YELLOW}[!] Tunnel connection dropped or rotating. Restarting immediately...${NC}"
    if [[ -n "${SSH_PID:-}" ]] && kill -0 "${SSH_PID}" 2>/dev/null; then
        kill "${SSH_PID}" 2>/dev/null || true
        for _ in {1..10}; do
            if ! kill -0 "${SSH_PID}" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 "${SSH_PID}" 2>/dev/null; then
            kill -9 "${SSH_PID}" 2>/dev/null || true
        fi
    fi
    # If tunnel died prematurely (under 30s), rotate host and back off slightly
    if [[ ${COUNT} -lt 30 ]]; then
        HOST_INDEX=$(( (HOST_INDEX + 1) % ${#CANDIDATE_HOSTS[@]} ))
        sleep 2
    fi
done
