#!/usr/bin/env bash
# ==============================================================================
# Zed Remote - Automated One-Shot Compilation & Installation Suite
# Compiles the Rust host daemon and the mobile clients (Compose / Flutter).
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

TARGET="${1:-all}"

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
    log_warn "Rust/Cargo not detected."
fi

# Check Java / JDK
if command -v java &>/dev/null; then
    log_success "Found Java: $(java -version 2>&1 | head -n 1)"
else
    log_warn "JDK not detected (needed for Jetpack Compose Android build)."
fi

# Check Flutter
if command -v flutter &>/dev/null; then
    log_success "Found Flutter: $(flutter --version | head -n 1)"
fi

echo ""

# ------------------------------------------------------------------------------
# 2. Build Host Daemon (Rust)
# ------------------------------------------------------------------------------
if [[ "$TARGET" == "all" || "$TARGET" == "daemon" ]]; then
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
fi

# ------------------------------------------------------------------------------
# 3. Build Mobile App
# ------------------------------------------------------------------------------
if [[ "$TARGET" == "flutter" ]]; then
    log_info "Building Flutter Mobile App (app/)..."
    if command -v flutter &>/dev/null; then
        cd "$ROOT_DIR/app"
        flutter pub get
        flutter build apk --release
        log_success "Flutter APK generated in app/build/app/outputs/flutter-apk/app-release.apk"
        cd "$ROOT_DIR"
    else
        log_error "Flutter command not found in PATH."
    fi
else
    # Default: Native Android Jetpack Compose app (Material 3)
    log_info "Step 3/3: Building Jetpack Compose Android Client (android/)..."

    if [ -f "$ROOT_DIR/android/gradlew" ]; then
        cd "$ROOT_DIR/android"
        chmod +x gradlew
        GRADLE_TASK="assembleRelease"
        if [[ "$TARGET" == "debug" ]]; then
            GRADLE_TASK="assembleDebug"
        fi
        log_info "Running: ./gradlew $GRADLE_TASK"
        if ./gradlew "$GRADLE_TASK"; then
            log_success "Android APK built successfully!"
            find app/build/outputs/apk -name "*.apk" -type f 2>/dev/null | while read -r apk; do
                log_success "Artifact: $apk"
            done
        else
            log_warn "Gradle build did not complete. Check Android SDK and JDK settings."
        fi
        cd "$ROOT_DIR"
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}                 ZED REMOTE COMPILATION FINISHED!                       ${NC}"
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "Helpful commands:"
echo -e "  1. Inject daemon into official Zed: ${CYAN}./tools/inject-daemon.sh${NC}"
echo -e "  2. Start bunker tunnel:             ${CYAN}./tools/bunker-tunnel.sh${NC}"
echo -e "  3. Build Flutter instead:           ${CYAN}./build-all.sh flutter${NC}"
echo -e "  4. Build Compose Release APK:       ${CYAN}./build-all.sh compose${NC}"
echo -e "${GREEN}${BOLD}========================================================================${NC}\n"
