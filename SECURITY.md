# Security Model & Threat Assessment

Because Zed Remote provides administrative access to your desktop machine over network connections, security is central to its architectural design.

---

## Network Isolation

- **Private Mesh Only**: The host daemon does not bind to public IP interfaces (`0.0.0.0`). It binds strictly to local overlay interfaces provided by WireGuard or Tailscale (`100.x.y.z`) or `127.0.0.1`.
- **No Port Forwarding**: The setup does not require opening public firewall ports or exposing endpoints via public reverse proxies.
- **Mesh Encryption**: Tailscale and WireGuard encrypt all host-to-mobile network packets point-to-point at the kernel wire level.

---

## Authentication and Transport Security

- **TLS Encryption**: WebSockets utilize TLS encryption backed by locally trusted mesh certificates (`rustls`).
- **Pre-Shared Bearer Tokens**: Handshake requests must present a pre-shared, cryptographically secure JWT in the request header (`Authorization: Bearer <TOKEN>`) or via query parameter handshake for WebSocket clients.
- **Timing-Safe Validation**: Token comparison is performed using constant-time string comparison algorithms to prevent timing attacks.

---

## Tool Execution Guardrails

When AI agents execute commands on your host laptop, safety bounds are enforced:

- **Permission Interception**: Critical operations (shell commands, file modifications) require explicit confirmation via `session/request_permission` prompts.
- **Command Blocklists**: The daemon can be configured to automatically deny high-risk execution strings (e.g., `rm -rf /`, `sudo`, destructive disk commands, fork bombs) regardless of mobile input.
- **Workspace Sandboxing**: File modifications are restricted to the active workspace directory unless explicitly overridden by configuration.
