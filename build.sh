#!/usr/bin/env bash
# ==============================================================================
# Zed Remote - Automated One-Shot Compilation & Installation Suite
# Compiles both the high-performance Rust host daemon and the Flutter mobile client.
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

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
log_info "Step 1/4: Checking system build prerequisites..."

MISSING_TOOLS=()

# Check Rust / Cargo
if command -v cargo &>/dev/null; then
    RUST_VERSION="$(rustc --version 2>/dev/null || cargo --version)"
    log_success "Found Rust toolchain: $RUST_VERSION"
elif [ -f "$HOME/.cargo/bin/cargo" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    log_success "Found Rust toolchain in ~/.cargo/bin: $(cargo --version)"
else
    log_warn "Rust/Cargo not detected in PATH."
    echo -e "       To install Rust, run: ${CYAN}curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh${NC}"
    MISSING_TOOLS+=("cargo")
fi

# Check Flutter / Dart
if command -v flutter &>/dev/null; then
    log_success "Found Flutter: $(flutter --version | head -n 1)"
elif [ -f "$HOME/flutter/bin/flutter" ]; then
    export PATH="$HOME/flutter/bin:$PATH"
    log_success "Found Flutter in ~/flutter/bin: $(flutter --version | head -n 1)"
else
    log_warn "Flutter SDK not detected in PATH."
    MISSING_TOOLS+=("flutter")
fi

# Check Python 3
if command -v python3 &>/dev/null; then
    log_success "Found Python: $(python3 --version)"
else
    log_warn "Python 3 not detected."
    MISSING_TOOLS+=("python3")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo ""
    log_warn "Some build tools are missing (${MISSING_TOOLS[*]}). Proceeding with available targets..."
fi

echo ""

# ------------------------------------------------------------------------------
# 2. Build Host Daemon (Rust)
# ------------------------------------------------------------------------------
log_info "Step 2/4: Compiling Rust Host Daemon (zed-remote-daemon)..."

if command -v cargo &>/dev/null; then
    cd "$ROOT_DIR/daemon"
    log_info "Running: cargo build --release"
    cargo build --release
    
    DAEMON_BIN="$ROOT_DIR/daemon/target/release/zed-remote-daemon"
    if [ -f "$DAEMON_BIN" ]; then
        log_success "Daemon compiled successfully: $DAEMON_BIN"
        
        # Optional installation to /usr/local/bin or ~/.local/bin
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
# 3. Build Mobile App (Flutter APK / Bundle)
# ------------------------------------------------------------------------------
log_info "Step 3/4: Building Flutter Mobile Application (app/)..."

if command -v flutter &>/dev/null; then
    cd "$ROOT_DIR/app"
    
    log_info "Fetching Flutter packages..."
    flutter pub get
    
    log_info "Running flutter analyze..."
    flutter analyze
    
    TARGET_BUILD="${1:-apk}"
    
    case "$TARGET_BUILD" in
        apk)
            log_info "Building release Android APK (flutter build apk --release)..."
            if flutter build apk --release; then
                APK_PATH="$ROOT_DIR/app/build/app/outputs/flutter-apk/app-release.apk"
                log_success "APK created successfully: $APK_PATH"
            else
                log_warn "Android toolchain / Java not configured; building bundle or skipping full APK link."
            fi
            ;;
        bundle)
            log_info "Building release Android App Bundle (AAB)..."
            flutter build appbundle --release
            ;;
        linux)
            log_info "Building Linux Desktop Client..."
            flutter build linux --release
            ;;
        web)
            log_info "Building Progressive Web App (PWA)..."
            flutter build web --release
            ;;
        *)
            log_info "Building release APK..."
            flutter build apk --release || true
            ;;
    esac
    cd "$ROOT_DIR"
else
    log_warn "Skipping Flutter app build (flutter not available)."
fi

echo ""

# ------------------------------------------------------------------------------
# 4. Generate Zero-Trust Pairing Credentials
# ------------------------------------------------------------------------------
log_info "Step 4/4: Initializing Zero-Knowledge Bunker Tunnel credentials..."

if command -v python3 &>/dev/null && [ -f "$ROOT_DIR/daemon/scripts/bunker_tunnel.py" ]; then
    python3 "$ROOT_DIR/daemon/scripts/bunker_tunnel.py" pair
fi

echo ""
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}                 ZED REMOTE COMPILATION FINISHED!                       ${NC}"
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "Next Steps:"
echo -e "  1. Start the encrypted tunnel:  ${CYAN}python3 daemon/scripts/bunker_tunnel.py run${NC}"
echo -e "  2. Start the daemon in Zed or:  ${CYAN}~/.local/bin/zed-remote-daemon --port 8443${NC}"
echo -e "  3. Scan the terminal QR code in your mobile app to link instantly off-the-grid!"
echo -e "${GREEN}${BOLD}========================================================================${NC}\n"
