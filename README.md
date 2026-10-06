# Zed Remote

> Control your local Zed AI sessions, approve agent tool permissions, and execute Git workflows directly from your mobile phone.

Zed Remote bridges your desktop development environment running the Zed editor with a native mobile client over a secure, encrypted tunnel. By intercepting the Agent Client Protocol (ACP) JSON-RPC streams between Zed and agents like AntiGravity, Zed Remote enables full prompt control, streaming thoughts, tool permission approval, and Git staging without needing a heavy remote graphical workspace.

---

## Features

* 💬 **Remote ACP Agent Control**: Stream conversation turns, agent reasoning chunks, and prompt history to your phone.
* 🛡️ **Remote Tool Authorization**: Receive push notifications and approve or reject file edits or terminal commands triggered by AI agents on your desktop.
* 🌿 **Mobile Git Operations**: Inspect modified files, review diffs, stage changes, write commit messages, and push to remote repositories directly from mobile.
* ⚡ **Lightweight Architecture**: Driven by a high-performance Rust daemon on the host machine and a responsive Flutter app on mobile.
* 🏰 **Bunker Tunnel (Firewall & DPI Resistant)**: Bypasses Fortinet, corporate firewalls, and hostel restrictions using outbound SSH over port 443 with zero-knowledge AES-256-GCM rendezvous and instant QR-code mobile pairing.
* 🔒 **End-to-End Private Mesh**: Also supports direct binding to WireGuard or Tailscale overlay networks.

---

## Repository Structure

| Path | Component | Description |
| --- | --- | --- |
| `daemon/` | Rust Host Daemon & Bunker Runner | Proxy binary that intercepts Zed stdio, exposes WebSockets, and manages Git operations. Includes `bunker_tunnel.py`. |
| `app/` | Flutter Mobile Client | Mobile application for iOS and Android with dual-panel UI, QR pairing, and auto-rotating tunnel sync. |
| `shared/` | Protocol Definitions | JSON-RPC method schemas and ACP payload specifications. |
| `docs/` | System Documentation | Architecture specifications, security model, and setup guides. |

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                   Desktop Workstation                  │
│                                                        │
│   ┌──────────────┐                 ┌───────────────┐   │
│   │  Zed Editor  │◄── Stdio IPC ──►│ AntiGravity   │   │
│   └──────▲───────┘   (NDJSON-RPC)  │  (AI Agent)   │   │
│          │                         └───────▲───────┘   │
│          └───────────────┬─────────────────┘           │
│                          │                             │
│             ┌────────────▼────────────┐                │
│             │   zed-remote-daemon     │                │
│             │  (Rust Tokio Gateway)   │                │
│             └────────────┬────────────┘                │
│                          │                             │
│             ┌────────────▼────────────┐                │
│             │   Bunker Tunnel Runner  │                │
│             │  (SSH 443 + AES-256-GCM)│                │
│             └────────────┬────────────┘                │
└──────────────────────────┼─────────────────────────────┘
                           │ Outbound TCP 443 (DPI Proof)
                           ▼
          Pinggy Relay + ntfy Encrypted Rendezvous
                           ▲
                           │ Decrypts with Scanned Key
              ┌────────────┴────────────┐
              │   Flutter Mobile App    │
              │  (Agent & Git Control)  │
              └─────────────────────────┘
```

---

## Quick Start (Bunker Tunnel - Recommended for Firewalls)

### 1. Pair Laptop & Phone via Terminal QR Code

On your laptop:

```bash
python3 daemon/scripts/bunker_tunnel.py pair
```

A clean ASCII QR code will appear in your terminal containing your zero-knowledge encryption key and secret rendezvous topic.

### 2. Start the Bunker Tunnel Supervisor

```bash
python3 daemon/scripts/bunker_tunnel.py run
```

### 3. Connect Mobile App

1. Open **Zed Remote** on your phone.
2. Tap the settings gear icon and switch to **Bunker Mode**.
3. Scan the terminal QR code or paste the pairing URI.
4. Your phone automatically syncs with the live tunnel and reconnects seamlessly across dynamic rotations!

---

## Traditional Mesh Setup (Tailscale)

If you prefer Tailscale:
1. Connect both laptop and phone to your Tailnet.
2. Launch `zed-remote-daemon` on `100.x.y.z:8443`.
3. Enter your Tailscale IP in the mobile app settings.
