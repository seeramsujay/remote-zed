# Zed Remote

> Control your local Zed AI sessions, approve agent tool permissions, and execute Git workflows directly from your mobile phone.

Zed Remote bridges your desktop development environment running the Zed editor with a native mobile client over a secure, encrypted tunnel. By intercepting the Agent Client Protocol (ACP) JSON-RPC streams between Zed and agents like AntiGravity, Zed Remote enables full prompt control, streaming thoughts, tool permission approval, and Git staging without needing a heavy remote graphical workspace.

---

## Features

* 💬 **Remote ACP Agent Control**: Stream conversation turns, agent reasoning chunks, and prompt history to your phone.
* 🛡️ **Remote Tool Authorization**: Receive push notifications and approve or reject file edits or terminal commands triggered by AI agents on your desktop.
* 🌿 **Mobile Git Operations**: Inspect modified files, review diffs, stage changes, write commit messages, and push to remote repositories directly from mobile.
* ⚡ **Lightweight Architecture**: Driven by a high-performance Rust daemon on the host machine and a responsive Flutter app on mobile.
* 🔒 **End-to-End Private Mesh**: Binds directly to private WireGuard/Tailscale overlay networks so your machine is never exposed to the public internet.

---

## Repository Structure

| Path | Component | Description |
| --- | --- | --- |
| `daemon/` | Rust Host Daemon | Proxy binary that intercepts Zed stdio, exposes WebSockets, and manages Git operations. |
| `app/` | Flutter Mobile Client | Mobile application for iOS and Android built using `acp_dart`. |
| `shared/` | Protocol Definitions | JSON-RPC method schemas and ACP payload specifications. |
| `docs/` | System Documentation | Architecture specifications, security model, and setup guides. |

---

## Architecture Overview

Zed Remote places a lightweight proxy daemon between Zed and the target AI agent executable:

1. **Stdio Interception**: Zed launches `zed-remote-daemon`, which spawns the agent binary (e.g., AntiGravity) as a child process.
2. **Protocol Proxying**: JSON-RPC frames passing over `stdin`/`stdout` are parsed and mirrored to a secure WebSocket server.
3. **Mobile Stream**: The Flutter app connects over Tailscale, rendering real-time streaming text and interactive tool permission cards.
4. **Out-of-Band Workflows**: Git commits, pushes, and host telemetry requests bypass the editor UI and execute directly via native host calls.

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
└──────────────────────────┼─────────────────────────────┘
                           │
             Tailscale / WireGuard (WSS + JWT)
                           │
              ┌────────────▼────────────┐
              │   Flutter Mobile App    │
              │  (Agent & Git Control)  │
              └─────────────────────────┘
```

---

## Quick Start

### 1. Build and Install the Host Daemon

```bash
cd daemon
cargo build --release
sudo cp target/release/zed-remote-daemon /usr/local/bin/
```

### 2. Configure Zed Settings

Add `zed-remote-daemon` as a custom ACP agent in your Zed `settings.json` file:

```json
{
  "agent_servers": {
    "AntiGravity-Remote": {
      "type": "custom",
      "command": "/usr/local/bin/zed-remote-daemon",
      "args": [
        "--target-command", "/usr/local/bin/antigravity",
        "--target-args", "acp",
        "--port", "8443"
      ]
    }
  }
}
```

### 3. Mobile Setup

1. Connect your phone to your Tailscale network.
2. Open the **Zed Remote Mobile App**.
3. Enter your host laptop's Tailscale IP address (`100.x.y.z:8443`) and your secret authentication token.
