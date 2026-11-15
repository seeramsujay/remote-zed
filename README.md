# Zed Remote

> Control your local Zed AI sessions, approve agent tool permissions, execute Git workflows, run interactive shell commands, and explore/open project folders directly from your mobile phone.

Zed Remote bridges your desktop development environment running the Zed editor with a native mobile client over a secure, encrypted tunnel. By intercepting the Agent Client Protocol (ACP) JSON-RPC streams between Zed and agents like AntiGravity, Zed Remote enables full prompt control, streaming thoughts, tool permission approval, interactive terminal execution, filesystem browsing, and Git staging without needing a heavy remote graphical workspace.

---

## Features

* 💬 **Remote ACP Agent Control**: Stream conversation turns, agent reasoning chunks, and prompt history to your phone.
* 🛡️ **Remote Tool Authorization**: Receive push notifications and approve or reject file edits or terminal commands triggered by AI agents on your desktop.
* 💻 **In-App Mobile Terminal (Termux Style)**: Interactive Linux terminal with virtual quick-keys (`TAB`, `~`, `|`, `..`, history recall) to start off-the-grid projects, run `mkdir`, `cargo new`, or compile binaries.
* 📁 **Remote Filesystem Explorer & Workspace Switcher**: Navigate host folders, create new project directories, and tap **"Set Workspace"** to open that folder immediately inside the desktop Zed GUI via local socket IPC.
* 🌿 **Mobile Git Operations**: Inspect modified files, review diffs, stage changes, write commit messages, and push to remote repositories directly from mobile.
* 🎨 **Material 3 / Material You**: Native Android Jetpack Compose app featuring dynamic color theming, edge-to-edge layout, and obsidian dark palettes.
* 🏰 **Bunker Tunnel (Firewall & DPI Resistant)**: Bypasses Fortinet, corporate firewalls, and hostel restrictions using outbound SSH over port 443 with zero-knowledge AES-256-GCM rendezvous and instant QR-code mobile pairing.
* 🔒 **Zero Eavesdropping**: Dynamic tunnel endpoints are encrypted with AES-256-GCM using keys scanned directly from your terminal. No third party or intermediary sees your endpoint or traffic.

---

## Two Integration Options for Official Zed

You have two simple ways to link Zed Remote with official Zed desktop releases without compiling Zed from source:

### 🚀 Option 1: Daemon Injection (`settings.json`) — Recommended
Configures `zed-remote-daemon` as an ACP agent server in `~/.config/zed/settings.json`.
- **Survives official Zed updates**: Zed's auto-updater replaces the app binary, but your `settings.json` stays intact.
- **Full AI control**: Complete interception of agent reasoning, file edits, and tool approvals.
- **Desktop Window Control**: Opening folders on your phone automatically calls `zed <path>` over `~/.local/share/zed/zed-stable.sock` to open that project in your Zed GUI.

Run:
```bash
./tools/inject-daemon.sh
```

### 🧩 Option 2: Zed Dev Extension
Installs a native Zed extension from `extensions/zed-remote` into Zed's dev extension path.
- **Lifecycle Management**: Zed starts the daemon automatically as an MCP context server.
- **Slash Commands**: Adds `/bunker status` and `/bunker pair` commands directly inside Zed's Agent and Assistant panels.

Run:
```bash
./tools/install-extension.sh
```
*(Or in Zed: Press `Ctrl+Shift+P` -> `zed: install dev extension` -> choose `extensions/zed-remote`)*

---

## Repository Structure

| Path | Component | Description |
| --- | --- | --- |
| `android/` | Android Client (Jetpack Compose) | Native Material 3 app with Dynamic Colors, Termux-style terminal, filesystem browser, and Bunker QR rendezvous. |
| `daemon/` | Rust Host Daemon & Bunker Runner | Proxy binary that intercepts Zed stdio, exposes dual HTTP REST + WebSocket endpoints, and manages terminal/Git execution. |
| `extensions/`| Zed Dev Extension | Native Zed extension (`extension.toml`, Wasm crate) with MCP server and `/bunker` slash command. |
| `tools/` | Automation & Security Scripts | `bunker-tunnel.sh` (AES-256-GCM rendezvous), `inject-daemon.sh`, `install-extension.sh`, and `sync-zed-fork.sh`. |
| `patches/` | Zed Upstream Patches | `zed-mobile-gateway.patch` for building custom Zed desktop gateway forks if desired. |
| `app/` | Flutter Mobile Client | Alternative cross-platform Flutter mobile client. |

---

## Quick Start (Bunker Tunnel - Fortinet Bypass)

### 1. Launch the Bunker Tunnel & QR Pairing

On your laptop:

```bash
./tools/bunker-tunnel.sh
```

A clean ASCII QR code will appear in your terminal containing your 256-bit AES key and ephemeral high-entropy (48+ hex char) rendezvous channel:

```
📱 SCAN THIS QR CODE IN ZED REMOTE ANDROID APP:
Topic: zed-bunker-79f82b4a901e...
Key:   [REDACTED AES-256-GCM KEY]
```

### 2. Connect Your Mobile App

1. Open **Zed Remote** on your Android phone.
2. Tap the QR scanner icon on the pairing screen.
3. Scan the terminal QR code.
4. The app resolves the tunnel from the rendezvous channel, decrypts it on-device with AES-256-GCM, and connects immediately!

---

## Upstream Zed Fork Maintenance

If you ever wish to keep your GitHub fork updated with official upstream releases:

```bash
./tools/sync-zed-fork.sh
```
This fetches `zed-industries/zed:main`, rebases `feature/mobile-gateway` on your fork (`seeramsujay/zed`), and pushes the updated branch.
