#!/usr/bin/env bash
# ==============================================================================
# Zed Remote - Automated One-Shot Compilation & Installation Suite
# Compiles the Rust host daemon and the Material 3 Jetpack Compose Android app.
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

log_info() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}${BOLD}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}${BOLD}[ERROR]${NC} $1" >&2
}

echo -e "${CYAN}${BOLD}"
cat << 'EOF'
  ______        _   ____                      _       
 |__  /  ___ __| | |  _ \ ___ _ __ ___   ___ | |_ ___ 
   / /  / _ \ _` | | |_) / _ \ '_ ` _ \ / _ \| __/ _ \
  / /__|  __/ (_| | |  _ <  __/ | | | | | (_) | ||  __/
 /_____\___|\__,_| |_| \_\___|_| |_| |_|\___/ \__\___|
EOF
echo -e "${NC}"
echo -e "${BOLD}Zed Remote: One-Shot Build & Packaging Suite${NC}"
echo -e "Directory: ${ROOT_DIR}\n"

# ------------------------------------------------------------------------------
# 1. Dependency & Toolchain Verification
# ------------------------------------------------------------------------------
log_info "Step 1/3: Checking build toolchains..."

# Check Rust / Cargo
if command -v cargo &>/dev/null; then
    log_success "Found Rust: $(cargo --version)"
elif [ -f "$HOME/.cargo/bin/cargo" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    log_success "Found Rust in ~/.cargo/bin: $(cargo --version)"
else
    log_warn "Rust/Cargo not detected. To install: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

# Check Java / JDK
if command -v java &>/dev/null; then
    log_success "Found Java: $(java -version 2>&1 | head -n 1)"
else
    log_warn "JDK not detected. Install OpenJDK 17+ for Android Gradle builds."
fi

echo ""

# ------------------------------------------------------------------------------
# 2. Build Host Daemon (Rust)
# ------------------------------------------------------------------------------
log_info "Step 2/3: Compiling Rust Host Daemon (zed-remote-daemon)..."

if command -v cargo &>/dev/null; then
    cd "$ROOT_DIR/daemon"
    log_info "Building release binary..."
    cargo build --release
    
    DAEMON_BIN="$ROOT_DIR/daemon/target/release/zed-remote-daemon"
    if [ -f "$DAEMON_BIN" ]; then
        log_success "Daemon compiled successfully: $DAEMON_BIN"
        INSTALL_DIR="$HOME/.local/bin"
        mkdir -p "$INSTALL_DIR"
        cp "$DAEMON_BIN" "$INSTALL_DIR/"
        log_success "Installed binary to $INSTALL_DIR/zed-remote-daemon"
    fi
    cd "$ROOT_DIR"
else
    log_warn "Skipping daemon compilation (cargo not available)."
fi

echo ""

# ------------------------------------------------------------------------------
# 3. Build Android Mobile App (Material 3 Jetpack Compose)
# ------------------------------------------------------------------------------
log_info "Step 3/3: Building Jetpack Compose Android Client (android/)..."

if [ -f "$ROOT_DIR/android/gradlew" ]; then
    cd "$ROOT_DIR/android"
    chmod +x gradlew
    TARGET="${1:-assembleDebug}"
    log_info "Running: ./gradlew $TARGET"
    if ./gradlew "$TARGET"; then
        log_success "Android APK built successfully!"
        find app/build/outputs/apk -name "*.apk" -type f 2>/dev/null | while read -r apk; do
            log_success "Artifact: $apk"
        done
    else
        log_warn "Gradle build did not complete. Check Android SDK and JDK settings."
    fi
    cd "$ROOT_DIR"
fi

echo ""
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}                 ZED REMOTE COMPILATION FINISHED!                       ${NC}"
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "Helpful commands:"
echo -e "  1. Inject daemon into official Zed: ${CYAN}./tools/inject-daemon.sh${NC}"
echo -e "  2. Start bunker tunnel (Fortinet bypass): ${CYAN}./tools/bunker-tunnel.sh${NC}"
echo -e "  3. Sync Zed GitHub fork:            ${CYAN}./tools/sync-zed-fork.sh${NC}"
echo -e "${GREEN}${BOLD}========================================================================${NC}\n"
