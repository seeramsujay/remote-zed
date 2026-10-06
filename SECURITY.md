# Security Model & Threat Assessment

Because Zed Remote provides administrative access to your desktop machine over network connections, security is central to its architectural design.

---

## 1. Network Transports & Firewall Resistance

Zed Remote supports two connection architectures:
1. **Direct Private Mesh**: WireGuard or Tailscale overlay network.
2. **Bunker Tunnel (Zero-Trust, DPI & Fortinet-Resistant)**:
   - For enterprise environments, universities, and hotel networks where firewalls (such as Fortinet, Palo Alto, or Cisco ASA) block WireGuard UDP and VPN protocols via Deep Packet Inspection (DPI).
   - Egresses over standard **SSH over TCP Port 443** (via Pinggy or custom port 443 relays), which mimics normal HTTPS/SSL web traffic.
   - Operates with **zero inbound port forwarding** and **zero public exposure**.

---

## 2. Zero-Knowledge Rendezvous & QR Pairing

When utilizing dynamic public relays (such as Pinggy) that rotate connection URLs:
- **AES-256-GCM AEAD Encryption**: The ephemeral connection URL (`tcp://...:port`) is never published in plaintext. The host laptop encrypts the rendezvous payload using a locally generated 256-bit symmetric Bunker Key before dispatching to pub/sub brokers (`ntfy.sh`).
- **Terminal QR Code Handshake**: The host CLI (`bunker_tunnel.py pair`) prints an ASCII QR code containing:
  - Cryptographically random ntfy topic name
  - 256-bit AES-GCM decryption key
  - Pre-shared daemon authentication bearer token
- **Zero-Knowledge Broker**: The notification broker (`ntfy.sh`) sees only high-entropy random ciphertext. Even if an adversary intercepts the topic, they cannot decrypt the target URL without the key scanned from your laptop's screen.
- **Tampering Resistance**: AES-GCM includes a 16-byte Poly1305/GHASH authentication tag. Any tampering or packet alteration during relay triggers an immediate authentication rejection on mobile.

---

## 3. Application Authentication & In-Transit Security

- **Constant-Time Verification**: Handshake bearer tokens are validated using constant-time string comparison algorithms (`subtle::ConstantTimeEq` / `hmac.compare_digest`), preventing timing side-channel attacks.
- **Probe Rejection**: Any scanner probing the dynamic TCP port is disconnected immediately if the valid Bearer token is not presented in the opening WebSocket frame.

---

## 4. Tool Execution Guardrails

When AI agents execute commands on your host laptop, safety bounds are enforced:

- **Permission Interception**: Critical operations (shell commands, file modifications) require explicit confirmation via `session/request_permission` prompts forwarded to mobile lock screens.
- **Command Blocklists**: The daemon automatically denies high-risk execution strings (e.g., `rm -rf /`, `sudo`, destructive disk commands, fork bombs) regardless of mobile input.
- **Workspace Sandboxing**: File modifications are restricted to the active workspace directory unless explicitly overridden by configuration.
