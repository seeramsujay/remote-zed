#!/usr/bin/env bash
# ==============================================================================
# Zed Remote - Automated One-Line Host Installer
# ==============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/seeramsujay/remote-zed/main/install.sh | bash
# ==============================================================================

set -euo pipefail

# Colors
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m"

echo -e "${CYAN}${BOLD}"
cat << 'EOF'
  ______        _   ____                      _       
 |__  /  ___ __| | |  _ \ ___ _ __ ___   ___ | |_ ___ 
   / /  / _ \ _` | | |_) / _ \ '_ ` _ \ / _ \| __/ _ \
  / /__|  __/ (_| | |  _ <  __/ | | | | | (_) | ||  __/
 /_____\___|\__,_| |_| \_\___|_| |_| |_|\___/ \__\___|
EOF
echo -e "${NC}"
echo -e "${BOLD}Zed Remote: One-Line Complete Host Installer${NC}"
echo -e "======================================================================\n"

# 1. Dependency checks
echo -e "${BLUE}${BOLD}[*] Step 1/4: Checking system dependencies...${NC}"
MISSING_PKGS=()
for cmd in curl ssh python3 openssl; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_PKGS+=("$cmd")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}[!] Missing required packages: ${MISSING_PKGS[*]}${NC}"
    if command -v apt-get &>/dev/null; then
        echo -e "${BLUE}[*] Attempting to install missing packages via apt...${NC}"
        sudo apt-get update && sudo apt-get install -y "${MISSING_PKGS[@]}"
    else
        echo -e "${YELLOW}[!] Please install ${MISSING_PKGS[*]} and run this installer again.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}[✓] Dependencies verified.${NC}\n"

# 2. Setup installation directory
INSTALL_ROOT="${HOME}/.local/share/zed-remote"
echo -e "${BLUE}${BOLD}[*] Step 2/4: Installing Zed Remote scripts and configs to ${INSTALL_ROOT}...${NC}"

if command -v git &>/dev/null; then
    if [ -d "${INSTALL_ROOT}/.git" ]; then
        echo -e "${BLUE}[*] Updating existing installation...${NC}"
        cd "${INSTALL_ROOT}"
        git pull --quiet origin main || true
    else
        mkdir -p "${INSTALL_ROOT}"
        git clone --quiet --depth 1 https://github.com/seeramsujay/remote-zed.git "${INSTALL_ROOT}"
    fi
else
    mkdir -p "${INSTALL_ROOT}"
    curl -fsSL https://github.com/seeramsujay/remote-zed/archive/refs/heads/main.tar.gz | tar -xz -C "${INSTALL_ROOT}" --strip-components=1
fi

chmod +x "${INSTALL_ROOT}/tools/"*.sh
echo -e "${GREEN}[✓] Files installed successfully.${NC}\n"

# 3. Inject into Zed settings.json
echo -e "${BLUE}${BOLD}[*] Step 3/4: Injecting daemon into official Zed settings...${NC}"
"${INSTALL_ROOT}/tools/inject-daemon.sh"
echo -e "${GREEN}[✓] Official Zed integration complete.${NC}\n"

# 4. Link Dev Extension
echo -e "${BLUE}${BOLD}[*] Step 4/4: Linking Zed Dev Extension...${NC}"
"${INSTALL_ROOT}/tools/install-extension.sh"
echo -e "${GREEN}[✓] Dev Extension linked into Zed.${NC}\n"

# Install symlinks into ~/.local/bin
mkdir -p "${HOME}/.local/bin"
ln -sf "${INSTALL_ROOT}/tools/bunker-tunnel.sh" "${HOME}/.local/bin/zed-tunnel"
ln -sf "${INSTALL_ROOT}/tools/inject-daemon.sh" "${HOME}/.local/bin/zed-inject"

echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}               🎉 ZED REMOTE INSTALLATION COMPLETE! 🎉                ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo ""
echo -e "📱 ${BOLD}Step 1: Download Android App${NC}"
echo -e "   Download ${CYAN}zed-remote.apk${NC} from:"
echo -e "   ${CYAN}https://github.com/seeramsujay/remote-zed/releases${NC}"
echo ""
echo -e "🏰 ${BOLD}Step 2: Start Your Encrypted Bunker Tunnel${NC}"
echo -e "   Run this command in any terminal:"
echo -e "   ${CYAN}zed-tunnel${NC}"
echo -e "   (or: ${INSTALL_ROOT}/tools/bunker-tunnel.sh)"
echo ""
echo -e "📷 ${BOLD}Step 3: Scan QR Code${NC}"
echo -e "   Open the app on your phone, scan the terminal QR code, and you're paired!"
echo -e "${GREEN}${BOLD}======================================================================${NC}\n"
