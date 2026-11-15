#!/usr/bin/env bash
# ==============================================================================
# Zed Remote Daemon Injector (Official Zed Binary Integration)
# ==============================================================================
# Injects the Zed Remote Daemon into any official upstream release of Zed
# (deb, tarball, flathub, or nightly) via ~/.config/zed/settings.json.
#
# This completely eliminates the need to compile Zed from source (which requires
# 20GB+ RAM and takes 45+ minutes) whenever Zed updates.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ZED_CONFIG_DIR="${HOME}/.config/zed"
ZED_SETTINGS="${ZED_CONFIG_DIR}/settings.json"
DAEMON_BIN="${ROOT_DIR}/daemon/target/release/zed-remote-daemon"
GLOBAL_BIN="/usr/local/bin/zed-remote-daemon"

echo "======================================================================"
echo "          🚀 ZED REMOTE DAEMON INJECTOR FOR OFFICIAL ZED 🚀           "
echo "======================================================================"

mkdir -p "${ZED_CONFIG_DIR}"

USER_BIN="${HOME}/.local/bin/zed-remote-daemon"
TARGET_BIN="${USER_BIN}"
if [[ -f "${DAEMON_BIN}" ]]; then
    TARGET_BIN="${DAEMON_BIN}"
elif [[ -f "${USER_BIN}" ]]; then
    TARGET_BIN="${USER_BIN}"
elif [[ -f "${GLOBAL_BIN}" ]]; then
    TARGET_BIN="${GLOBAL_BIN}"
else
    echo "[*] Downloading prebuilt zed-remote-daemon binary..."
    mkdir -p "${HOME}/.local/bin"
    curl -fsSL https://github.com/seeramsujay/remote-zed/releases/download/v0.1.1/zed-remote-daemon-linux-x86_64.tar.gz | tar -xz -C "${HOME}/.local/bin" || true
    chmod +x "${USER_BIN}" 2>/dev/null || true
    if [[ -f "${USER_BIN}" ]]; then
        TARGET_BIN="${USER_BIN}"
    elif [[ -f "${GLOBAL_BIN}" ]]; then
        TARGET_BIN="${GLOBAL_BIN}"
    fi
fi

# Load or generate persistent bearer token
CONFIG_FILE="${HOME}/.config/zed-remote/bunker-session.json"
TOKEN="zed-secret-$(openssl rand -hex 16)"
if [[ -f "${CONFIG_FILE}" ]]; then
    TOKEN=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}')).get('token', '${TOKEN}'))")
fi

echo "[*] Configuring official Zed settings at ${ZED_SETTINGS}..."

python3 -c "
import json, os, shutil

settings_path = '${ZED_SETTINGS}'
if os.path.exists(settings_path):
    try:
        with open(settings_path, 'r') as f:
            data = json.load(f)
    except Exception:
        data = {}
else:
    data = {}

agent_servers = data.get('agent_servers', {})
target_agent = 'agy'
if shutil.which('agy'):
    target_agent = shutil.which('agy')
elif shutil.which('antigravity'):
    target_agent = shutil.which('antigravity')

agent_servers['AntiGravity-Remote'] = {
    'default_config_options': {
        'mode': 'yolo'
    },
    'type': 'custom',
    'command': '${TARGET_BIN}',
    'args': [
        '--target-command', target_agent,
        '--target-args', 'acp --dangerously-skip-permissions',
        '--port', '8443',
        '--auth-token', '${TOKEN}'
    ]
}
data['agent_servers'] = agent_servers

with open(settings_path, 'w') as f:
    json.dump(data, f, indent=2)

print('[+] Successfully injected AntiGravity-Remote agent server into ' + settings_path)
"

echo ""
echo "[✓] Injection complete! Whenever official Zed updates, your settings stay intact."
echo "[✓] Zed will automatically invoke zed-remote-daemon with full mobile proxy support."
echo ""
echo "To start the encrypted bunker tunnel for phone connectivity:"
echo "  ${SCRIPT_DIR}/bunker-tunnel.sh"
echo "======================================================================"
