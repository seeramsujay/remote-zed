<div align="center">

# ⚡ Zed Remote

**Control your local Zed AI sessions, approve agent tool permissions, execute Git workflows, and command host workspaces directly from your mobile phone.**

[![CI](https://github.com/seeramsujay/remote-zed/actions/workflows/ci.yml/badge.svg)](https://github.com/seeramsujay/remote-zed/actions/workflows/ci.yml)
[![Android](https://img.shields.io/badge/Platform-Android_12+-3DDC84?logo=android&logoColor=white)](https://android.com)
[![iOS](https://img.shields.io/badge/Platform-iOS_16+-000000?logo=apple&logoColor=white)](https://apple.com)
[![Jetpack Compose](https://img.shields.io/badge/UI-Jetpack_Compose_Material_3-4285F4?logo=jetpackcompose&logoColor=white)](https://developer.android.com/jetpack/compose)
[![Flutter](https://img.shields.io/badge/UI-Flutter_3-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Zed Compatible](https://img.shields.io/badge/Editor-Zed_Official-087EA4?logo=rust&logoColor=white)](https://zed.dev)
[![Tunnel Security](https://img.shields.io/badge/Tunnel-AES--256--GCM_%2B_SSH_443-purple?logo=wireguard&logoColor=white)](#bunker-tunnel-firewall-bypass)

<br/>

```bash
curl -fsSL https://raw.githubusercontent.com/seeramsujay/remote-zed/main/install.sh | bash
```

[Features](#key-features) •
[Quick Start](#quick-start) •
[Mobile Apps](#mobile-app-setup-android-ios) •
[Bunker Tunnel](#bunker-tunnel-firewall-bypass) •
[Desktop Integration](#zero-rebuild-integration-with-official-zed) •
[Architecture](#architecture) •
[Releases](#releases-cloud-builds)

</div>

---

## 💡 Why Zed Remote?

When working away from your desk—whether commuting, in a college hostel, or traveling—your primary machine stays running at your workstation. Modern development workflows rely on autonomous AI agents (like AntiGravity, Claude, or custom ACP agents) to refactor code, run tests, and execute bash commands.

**Traditional remote tools fail on mobile:**
- **VNC / RDP / Graphical Desktops**: Consume massive bandwidth, suffer high latency, and scale horribly to 6-inch phone screens.
- **Tailscale / WireGuard**: Frequently blocked on restrictive networks (e.g. Fortinet, college Wi-Fi, or corporate firewalls blocking UDP 41641).

**Zed Remote solves this at the protocol level:**
Instead of streaming pixels, Zed Remote intercepts the **Agent Client Protocol (ACP)** JSON-RPC streams over standard I/O pipes. It forwards token-by-token reasoning chunks, tool approval cards, and repository state directly to native **Android (Material 3 / Jetpack Compose or Flutter)** and **iOS (Flutter)** apps over a firewall-proof, AES-256-GCM encrypted tunnel.

---

## ✨ Key Features

| Feature | Description |
| :--- | :--- |
| 💬 **Real-Time ACP AI Stream** | Monitor streaming reasoning chunks, thoughts, and conversational turns with your desktop AI agent from anywhere. |
| 🛡️ **Remote Tool Authorization** | Receive instant prompts on your phone to approve or deny file edits, deletions, or terminal commands triggered by the agent. |
| 💻 **Termux-Style Shell** | Interactive mobile terminal equipped with a virtual quick-keys bar (`TAB`, `~`, `/`, `-`, `|`, `..`, `↑`, `↓`, `Ctrl+C`, `CLEAR`) for quick CLI tasks. |
| 📁 **Workspace Control & Folder Opening** | Browse remote directories, create new project folders, and tap **"Set Workspace"** to instantly open that project inside the desktop Zed GUI via local socket IPC. |
| 🌿 **Mobile Git Operations** | Review diffs with syntax highlighting, stage modified files, write commit messages, and push to GitHub/GitLab directly from your phone. |
| 🎨 **Material 3 / Material You** | Handcrafted native Jetpack Compose interface with Android 12+ wallpaper dynamic color extraction and obsidian dark mode. |
| 📱 **Dual UI Options (Compose & Flutter)** | Choose between native Jetpack Compose or Flutter depending on your preferred look and feel. |
| 🍏 **iOS / iPadOS Support** | Unsigned IPA ready to sideload via AltStore, Sideloadly, TrollStore, or LiveContainer. |
| 🏰 **Bunker Tunnel (Zero-Trust)** | Outbound reverse tunnel over SSH port 443 that bypasses Fortinet firewalls with zero-knowledge, 48-char random hex rendezvous and end-to-end AES-256-GCM encryption. |

---

## 🏗️ Architecture

Zed Remote places a lightweight proxy daemon between Zed and your AI agent executable, with an encrypted rendezvous for mobile devices:

```
┌────────────────────────────────────────────────────────┐
│                   Desktop Workstation                  │
│                                                        │
│   ┌──────────────┐                 ┌───────────────┐   │
│   │  Zed Editor  │◄── Stdio IPC ──►│  AntiGravity  │   │
│   └──────▲───────┘   (NDJSON-RPC)  │  (AI Agent)   │   │
│          │                         └───────▲───────┘   │
│          └───────────────┬─────────────────┘           │
│                          │                             │
│             ┌────────────▼────────────┐                │
│             │    zed-remote-daemon    │                │
│             │  • Dual HTTP & WS Engine│                │
│             │  • ACP Stream Router    │                │
│             │  • Git & Shell Executor │                │
│             └────────────┬────────────┘                │
│                          │                             │
│             ┌────────────▼────────────┐                │
│             │   Bunker Tunnel Script  │                │
│             │  (SSH 443 + AES-256-GCM)│                │
│             └────────────┬────────────┘                │
└──────────────────────────┼─────────────────────────────┘
                           │ Outbound TCP 443 (Firewall Proof)
                           ▼
          Pinggy Relay + ntfy Encrypted Rendezvous
                           ▲
                           │ Decrypts with Scanned Key
              ┌────────────┴────────────┐
              │ Mobile Clients          │
              │ • Android Jetpack M3    │
              │ • Android Flutter       │
              │ • iOS Flutter (IPA)     │
              └─────────────────────────┘
```

---

## 🚀 Quick Start

### ⚡ Complete One-Line Install (Laptop)

Run this single command on your laptop to install Zed Remote, configure Zed, and set up your bunker tunnel (interactive prompt allows enabling an automatic systemd background service):

```bash
curl -fsSL https://raw.githubusercontent.com/seeramsujay/remote-zed/main/install.sh | bash
```

#### 1. Bind your phone once:
```bash
zed-tunnel --bind
```
Scan the terminal QR code once in the mobile app. The session channel and AES-GCM encryption key are permanently saved on both devices.

#### 2. Everyday connection (no QR scanning needed):
```bash
zed-tunnel
```
Starts the tunnel and dynamically publishes encrypted updates to your phone in the background.

#### 3. Autostart & Service Management:
```bash
zed-tunnel --service enable   # Start automatically on system boot via systemd user service
zed-tunnel --service disable  # Revert to on-demand mode
zed-tunnel --inject           # Re-inject daemon into Zed settings.json
zed-tunnel --status           # Check tunnel and systemd service status
zed-tunnel -h                 # Display help and commands
zed-tunnel --update           # Update Zed Remote to latest release

# Note: You can use "zedt" as a shorthand for "zed-tunnel" anywhere!
```

---

### 📱 Mobile App Setup (Android & iOS)

Choose the client that fits your workflow:
- 🤖 **Native Jetpack Compose (Recommended)**: Download **`zed-remote.apk`** for Android 12+ dynamic Material You colors and fast UI rendering.
- 💙 **Flutter Mobile (Android)**: Download **`zed-remote-flutter.apk`** for the cross-platform Flutter experience.
- 🍏 **Flutter Mobile (iOS / iPadOS)**: Download **`zed-remote-ios-unsigned.ipa`** and sideload it via AltStore, Sideloadly, TrollStore, or LiveContainer.

1. **Install App**: Download your preferred client from [**Releases**](https://github.com/seeramsujay/remote-zed/releases).
2. **Scan QR Code**: Open the app, tap the **Scan QR** icon, and scan the terminal QR code printed by `zed-tunnel`.
3. **Control From Anywhere**: Prompt your agent, approve tool actions, run terminal commands, and open project folders off-the-grid!

---

## 🏰 Bunker Tunnel & Firewall Bypass

Standard mesh overlays like Tailscale or WireGuard use UDP (port 41641), which enterprise networks, university hostels, and Fortinet egress firewalls routinely block or throttle via Deep Packet Inspection (DPI).

**How the Bunker Tunnel works:**
1. **Outbound Port 443 Only**: Establishes an outbound reverse SSH tunnel over port 443 (indistinguishable from standard HTTPS traffic).
2. **Ephemeral Rendezvous**: Generates a cryptographically random topic (e.g. `zed-bunker-` + 48 hex characters) providing $10^{58}$ entropy, making collision or discovery impossible.
3. **AES-256-GCM Encryption**: The laptop encrypts the dynamic tunnel URL with a 256-bit symmetric key (`12-byte IV + ciphertext + 16-byte tag`) before posting to `ntfy.sh`.
4. **Zero Eavesdropping**: Third parties and relay servers see only random opaque ciphertext. The decryption key is scanned directly from your terminal and never transmitted over the network.

---

## 🧩 Zero-Rebuild Integration with Official Zed

You never need to maintain a custom fork of Zed or compile Zed's 20GB+ Rust codebase on your laptop. Choose either integration option:

### Option 1: Daemon Injection (`inject-daemon.sh`) — *Recommended*
Registers the proxy daemon in `~/.config/zed/settings.json`:
- **Survives official updates**: When official Zed updates via `apt`, `.deb`, or auto-updater, your settings stay intact.
- **Window Management**: Opening folders or setting workspaces on mobile automatically executes `zed <path>` over `~/.local/share/zed/zed-stable.sock` to open that folder in the desktop GUI.

```bash
./tools/inject-daemon.sh
```

### Option 2: Native Zed Dev Extension (`install-extension.sh`)
Symlinks the extension at `extensions/zed-remote` into Zed's dev extension path:
- Registers `zed-remote` as an MCP context server.
- Adds `/bunker status` and `/bunker pair` slash commands directly inside Zed's Agent panel.

```bash
./tools/install-extension.sh
```

---

## 📦 Releases & Cloud Builds

You don't need to heat up your laptop compiling APKs or IPAs. GitHub Actions automatically builds and publishes releases on GitHub's cloud runners for free:

```bash
# Tag and push to trigger automated cloud build
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions will compile in parallel:
- 🤖 **`zed-remote.apk`**: Native Material 3 / Jetpack Compose Android client.
- 💙 **`zed-remote-flutter.apk`**: Cross-platform Flutter Android client.
- 🍏 **`zed-remote-ios-unsigned.ipa`**: Unsigned iOS application bundle for AltStore / Sideloadly / TrollStore.
- 🐧 **`zed-remote-daemon-linux-x86_64.tar.gz`**: Precompiled high-performance Rust host daemon binary.

To build manually on your workstation:
```bash
# Build Compose APK locally
./build-all.sh compose

# Build Flutter APK locally
./build-all.sh flutter

# Build Rust daemon locally
./build-all.sh daemon
```

---

## 📂 Repository Structure

```
remote-zed/
├── android/            # Native Android App (Material 3, Jetpack Compose, dynamic colors)
│   ├── app/src/main/   # UI Screens, ViewModel, Terminal, Files, and Bunker client
│   └── build.gradle.kts
├── app/                # Cross-platform Flutter App (Android & iOS)
│   ├── lib/            # Dual-panel layout, ACP streaming, Terminal, Bunker crypto
│   └── pubspec.yaml
├── daemon/             # High-performance Rust host daemon (Tokio, ACP Proxy, Git & Shell engine)
│   ├── src/gateway/    # Dual HTTP REST/SSE and WebSocket gateway
│   ├── src/terminal/   # Terminal execution and remote filesystem operations
│   └── Cargo.toml
├── extensions/         # Native Zed Dev Extension
│   └── zed-remote/     # extension.toml, MCP context server, /bunker slash command
├── tools/              # One-shot automation scripts
│   ├── bunker-tunnel.sh# Fortinet-proof SSH 443 + AES-256-GCM tunnel & QR generator
│   ├── inject-daemon.sh# Automatic official Zed settings.json injector
│   └── install-extension.sh # Symlinks dev extension into Zed
├── install.sh          # One-line automated host installer
├── patches/            # Reference GPUI gateway patches for Zed desktop
├── build-all.sh        # Local one-shot compilation script
└── .github/workflows/  # Automated CI and release build pipelines
```
