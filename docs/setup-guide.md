# Zed Remote Setup & Operation Guide

This guide details end-to-end setup for the host daemon, the Zed editor configuration, and the mobile companion client.

---

## Prerequisites

1. **Host Machine**:
   - Linux (x86_64, aarch64) or macOS (Apple Silicon / Intel).
   - Rust toolchain (`cargo`, `rustc` 1.75+ recommended).
   - Zed Editor (v0.120+ with External Agents / ACP support).
   - AI Agent binary (e.g. `antigravity`, `claude-code`, etc.).
   - Tailscale or WireGuard installed and logged in.

2. **Mobile Device**:
   - iOS 15+ or Android 10+.
   - Tailscale mobile client connected to the same Tailnet as your host machine.

---

## 1. Host Daemon Installation

Compile and install `zed-remote-daemon` locally:

```bash
cd daemon
cargo build --release
sudo install -m 755 target/release/zed-remote-daemon /usr/local/bin/
```

Generate a secure authentication token for your mobile client:

```bash
# Generate a random 32-byte secret hex token
openssl rand -hex 32 > ~/.zed-remote/auth_token
chmod 600 ~/.zed-remote/auth_token
cat ~/.zed-remote/auth_token
```

---

## 2. Zed Editor Configuration

Open your Zed configuration file (`~/.config/zed/settings.json` on Linux or `~/Library/Application Support/Zed/settings.json` on macOS). Add or modify the `agent_servers` section:

```json
{
  "agent_servers": {
    "AntiGravity-Remote": {
      "type": "custom",
      "command": "/usr/local/bin/zed-remote-daemon",
      "args": [
        "--target-command", "antigravity",
        "--target-args", "acp",
        "--bind-host", "100.x.y.z",
        "--port", "8443",
        "--token-file", "/home/username/.zed-remote/auth_token"
      ],
      "env": {
        "RUST_LOG": "info"
      }
    }
  }
}
```

> **Note**: Replace `100.x.y.z` with your laptop's Tailscale IPv4 address (`tailscale ip -4`).

---

## 3. Mobile Client Configuration

1. Launch **Zed Remote** on your phone.
2. In the Settings tab:
   - **Host Address**: Enter your host Tailscale IP: `100.x.y.z:8443` (or MagicDNS name, e.g. `my-laptop.tailnet.ts.net:8443`).
   - **Auth Token**: Paste the generated bearer token from `~/.zed-remote/auth_token`.
   - **TLS Mode**: Toggle On (or Off for pure local WireGuard tunnel without TLS termination).
3. Tap **Connect**. Once the status dot turns green, your phone is linked to the desktop ACP stream.

---

## 4. Typical Remote Workflow

1. Open a workspace in Zed on your host machine before leaving.
2. From your mobile phone:
   - Send prompts in the **Agent Panel**.
   - Watch real-time streaming tokens and agent thought expansions.
   - When the agent attempts to run a build or edit a file, review the permission modal and tap **Approve**.
   - Switch to the **Repository Panel** to review git status, inspect modified line counts, enter a commit message, and tap **Push**.
   - Check the **Telemetry Bar** to ensure laptop battery and CPU levels are healthy.
