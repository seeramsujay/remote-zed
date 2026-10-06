#!/usr/bin/env bash
# ==============================================================================
# Bunker Tunnel Runner for Zed Remote (Firewall & DPI Resistant)
# Bypasses enterprise firewalls (Fortinet, Palo Alto) using Pinggy over port 443
# and encrypts dynamic rendezvous updates via AES-256-GCM.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/bunker_tunnel.py"

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required to run the bunker tunnel." >&2
    exit 1
fi

ACTION="${1:-run}"

case "$ACTION" in
    pair)
        python3 "$PYTHON_SCRIPT" pair "${@:2}"
        ;;
    run)
        python3 "$PYTHON_SCRIPT" run "${@:2}"
        ;;
    test)
        python3 "$PYTHON_SCRIPT" test-crypto
        ;;
    *)
        echo "Usage: $0 {pair|run|test}"
        exit 1
        ;;
esac
