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
echo -e "${BLUE}${BOLD}[*] Step 1/6: Checking system dependencies...${NC}"
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
echo -e "${BLUE}${BOLD}[*] Step 2/6: Installing Zed Remote scripts and configs to ${INSTALL_ROOT}...${NC}"

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
    curl -fsSL https://raw.githubusercontent.com/seeramsujay/remote-zed/archive/refs/heads/main.tar.gz | tar -xz -C "${INSTALL_ROOT}" --strip-components=1
fi

chmod +x "${INSTALL_ROOT}/tools/"*.sh
echo -e "${GREEN}[✓] Files installed successfully.${NC}\n"

# Download prebuilt daemon binary if not present
mkdir -p "${HOME}/.local/bin"
if [[ ! -f "${HOME}/.local/bin/zed-remote-daemon" ]]; then
    echo -e "${BLUE}[*] Fetching prebuilt zed-remote-daemon release binary...${NC}"
    curl -fsSL https://github.com/seeramsujay/remote-zed/releases/download/v0.1.1/zed-remote-daemon-linux-x86_64.tar.gz | tar -xz -C "${HOME}/.local/bin" || true
    chmod +x "${HOME}/.local/bin/zed-remote-daemon" 2>/dev/null || true
fi

# 3. Inject into Zed settings.json
echo -e "${BLUE}${BOLD}[*] Step 3/6: Injecting daemon into official Zed settings...${NC}"
"${INSTALL_ROOT}/tools/inject-daemon.sh"
echo -e "${GREEN}[✓] Official Zed integration complete.${NC}\n"

# 4. Link Dev Extension
echo -e "${BLUE}${BOLD}[*] Step 4/6: Linking Zed Dev Extension...${NC}"
"${INSTALL_ROOT}/tools/install-extension.sh"
echo -e "${GREEN}[✓] Dev Extension linked into Zed.${NC}\n"

# Install symlinks into ~/.local/bin
mkdir -p "${HOME}/.local/bin"
ln -sf "${INSTALL_ROOT}/tools/bunker-tunnel.sh" "${HOME}/.local/bin/zed-tunnel"
ln -sf "${INSTALL_ROOT}/tools/bunker-tunnel.sh" "${HOME}/.local/bin/zedt"
ln -sf "${INSTALL_ROOT}/tools/inject-daemon.sh" "${HOME}/.local/bin/zed-inject"

# 5. Shell Alias Option (zedt)
echo -e "${BLUE}${BOLD}[*] Step 5/6: Configuring Shell Shorthand (zedt)...${NC}"
PROMPT_ALIAS="y"
if [ -t 0 ]; then
    read -r -p "Would you like to configure shell alias 'zedt' for faster access? [Y/n]: " PROMPT_ALIAS || PROMPT_ALIAS="y"
elif [ -e /dev/tty ]; then
    read -r -p "Would you like to configure shell alias 'zedt' for faster access? [Y/n]: " PROMPT_ALIAS < /dev/tty || PROMPT_ALIAS="y"
fi

if [[ ! "${PROMPT_ALIAS,,}" =~ ^(n|no)$ ]]; then
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        if [[ -f "$rc" ]] && ! grep -q 'alias zedt=' "$rc"; then
            echo 'alias zedt="zed-tunnel"' >> "$rc"
        fi
    done
    echo -e "${GREEN}[✓] Alias 'zedt' -> 'zed-tunnel' configured.${NC}\n"
else
    echo -e "${CYAN}[*] Skipped shell rc alias. Binary symlink ~/.local/bin/zedt is ready.${NC}\n"
fi

# 6. Systemd Service Option
echo -e "${BLUE}${BOLD}[*] Step 6/6: Configuring Startup & Systemd Service...${NC}"
PROMPT_ANSWER="n"
if [ -t 0 ]; then
    # Interactive terminal
    read -r -p "Would you like to run zed-tunnel as a systemd user service automatically on startup? [y/N]: " PROMPT_ANSWER || PROMPT_ANSWER="n"
elif [ -e /dev/tty ]; then
    # Piped curl into bash, but user has interactive tty attached
    read -r -p "Would you like to run zed-tunnel as a systemd user service automatically on startup? [y/N]: " PROMPT_ANSWER < /dev/tty || PROMPT_ANSWER="n"
fi

if [[ "${PROMPT_ANSWER,,}" =~ ^(y|yes)$ ]]; then
    if command -v systemctl &>/dev/null; then
        echo -e "${BLUE}[*] Enabling and starting zed-tunnel systemd user service...${NC}"
        "${HOME}/.local/bin/zed-tunnel" --service enable
    else
        echo -e "${YELLOW}[!] systemctl not found; continuing in on-demand mode.${NC}"
    fi
else
    echo -e "${CYAN}[*] Configured for on-demand mode.${NC}"
    echo -e "    You can run '${CYAN}zed-tunnel${NC}' (or '${CYAN}zedt${NC}') whenever you want to connect,"
    echo -e "    or enable background autostart later with '${CYAN}zed-tunnel --service enable${NC}'."
fi

# Ensure ~/.local/bin is in PATH in profile if needed
if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    SHELL_RC=""
    if [[ "${SHELL:-}" =~ "zsh" ]]; then
        SHELL_RC="${HOME}/.zshrc"
    elif [[ "${SHELL:-}" =~ "bash" ]]; then
        SHELL_RC="${HOME}/.bashrc"
    fi
    if [[ -n "$SHELL_RC" ]] && [[ -f "$SHELL_RC" ]]; then
        # shellcheck disable=SC2016
        if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$SHELL_RC"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
        fi
    fi
fi

echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}               🎉 ZED REMOTE INSTALLATION COMPLETE! 🎉                ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo ""
echo -e "📱 ${BOLD}Step 1: Download the Mobile App${NC}"
echo -e "   • Native Jetpack Compose APK: ${CYAN}zed-remote.apk${NC} (Recommended)"
echo -e "   • Flutter Cross-Platform APK: ${CYAN}zed-remote-flutter.apk${NC}"
echo -e "   • Download latest from: ${CYAN}https://github.com/seeramsujay/remote-zed/releases${NC}"
echo ""
echo -e "🏰 ${BOLD}Step 2: Bind Your Phone Once${NC}"
echo -e "   Run: ${CYAN}zed-tunnel --bind${NC}  (or: ${CYAN}zedt --bind${NC})"
echo -e "   Scan the QR code once with your phone. The binding is saved permanently!"
echo ""
echo -e "🚀 ${BOLD}Step 3: Everyday Use${NC}"
echo -e "   Simply run: ${CYAN}zed-tunnel${NC}  (or: ${CYAN}zedt${NC})"
echo -e "   (No QR scan needed! Your phone reconnects automatically)."
echo ""
echo -e "ℹ️  ${BOLD}Help & Systemd Service Management${NC}"
echo -e "   • View all commands:    ${CYAN}zedt -h${NC}"
echo -e "   • Re-inject into Zed:   ${CYAN}zedt --inject${NC}"
echo -e "   • Enable autostart:     ${CYAN}zedt --service enable${NC}"
echo -e "   • Disable autostart:    ${CYAN}zedt --service disable${NC}"
echo -e "   • Update Zed Remote:    ${CYAN}zedt --update${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}\n"
