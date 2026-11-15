#!/usr/bin/env bash
# ==============================================================================
# Install Zed Remote Dev Extension into Zed
# ==============================================================================
# Links extensions/zed-remote into ~/.local/share/zed/extensions/work/zed-remote
# so official Zed loads it immediately without needing to recompile Zed or publish to registry.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="${SCRIPT_DIR}/../extensions/zed-remote"
ZED_EXT_DIR="${HOME}/.local/share/zed/extensions/work"
TARGET_LINK="${ZED_EXT_DIR}/zed-remote"

mkdir -p "${ZED_EXT_DIR}"
ln -sfn "${EXT_DIR}" "${TARGET_LINK}"

echo "======================================================================"
echo "          🧩 ZED REMOTE DEV EXTENSION INSTALLED 🧩                    "
echo "======================================================================"
echo "[+] Linked extension:"
echo "    ${EXT_DIR}"
echo "    -> ${TARGET_LINK}"
echo ""
echo "In Zed:"
echo "  1. Open Command Palette (Ctrl+Shift+P / Cmd+Shift+P)"
echo "  2. Run 'zed: reload extensions'"
echo "  3. Use slash command '/bunker status' in the Agent panel"
echo "======================================================================"
