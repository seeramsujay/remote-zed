# Zed Remote Mobile Client (Flutter)

A Flutter companion application for iOS and Android providing remote Agent Client Protocol (ACP) interaction, interactive tool permissions, out-of-band Git workflows, and host machine telemetry.

---

## Architecture

The mobile client is engineered for responsiveness and high information density on smartphone and tablet screens:

```
[Flutter UI Views]
   ├── AgentPanel (Streaming tokens, thought expansion, prompts)
   ├── RepositoryPanel (File list, diff inspection, staging, commit & push)
   ├── TelemetryBar (CPU, RAM, battery, power controls)
   └── PermissionDialog (Modal approval for tool calls)
           │
     [ChangeNotifier State Layer]
     (AgentState, GitState, TelemetryState)
           │
     [Service Layer]
     (AgentService, GitService, TelemetryService)
           │
     [WebSocketClient]
           │ (WSS over Tailscale)
           ▼
     [zed-remote-daemon]
```

---

## Features

- **Streaming AI Conversation**: Token-by-token real-time rendering using Markdown.
- **Collapsible Reasoning**: Expanding thought cards showing model internal deliberations without cluttering chat.
- **Interactive Tool Authorization**: Lock-screen modals to Approve or Reject `terminal/create` or file write actions.
- **Out-of-Band Git Control**: Inspect repository status, view syntax-highlighted diffs, select files to stage, write commit messages, and push directly to GitHub/GitLab.
- **Laptop Telemetry**: Live CPU and RAM usage, laptop battery percentage with charging status, and one-tap sleep/lock triggers.
- **Adaptive Layout**: Automatically transitions between tabbed view on phones and side-by-side dual panels on tablets.

---

## Configuration

In the in-app **Connection Settings** sheet (gear icon in the top right):
1. **Host IP**: Your host workstation's Tailscale IPv4 address (`100.x.y.z`).
2. **Port**: Default is `8443`.
3. **Bearer Token**: The secret authorization token configured on the host daemon.
4. **Use TLS**: Enable if your Tailscale network enforces HTTPS certificates.
