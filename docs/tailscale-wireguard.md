# Tailscale & WireGuard Network Setup

Zed Remote is intentionally engineered to avoid public port forwarding, dynamic DNS exposing your desktop, or relying on third-party cloud relays. Instead, it relies on point-to-point mesh networks powered by Tailscale or native WireGuard.

---

## 1. Why Tailscale?

- **Zero Configuration**: NAT traversal (DERP relays and STUN) automatically links your mobile phone on cellular networks directly to your laptop on home/hostel Wi-Fi.
- **Kernel-level WireGuard**: End-to-end ChaCha20-Poly1305 authenticated encryption ensures total confidentiality.
- **MagicDNS**: Your host laptop receives a predictable DNS name, e.g., `laptop.tailnet-xyz.ts.net`.
- **IP Stability**: Your laptop maintains a static 100.x.y.z IP address across all network transitions.

---

## 2. Host Configuration

Verify Tailscale is running on your host machine:

```bash
# Check status and retrieve Tailscale IP
tailscale status
tailscale ip -4
```

Configure `zed-remote-daemon` to bind strictly to your Tailscale IP:

```bash
zed-remote-daemon \
  --bind-host "$(tailscale ip -4)" \
  --port 8443 \
  --target-command antigravity \
  --target-args acp
```

---

## 3. Tailscale Access Control Lists (ACLs)

To lock down access even further, enforce Tailscale ACL rules in the Tailscale admin console:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:mobile-phones"],
      "dst": ["tag:workstations:8443"]
    }
  ],
  "tagOwners": {
    "tag:mobile-phones": ["autogroup:admin"],
    "tag:workstations": ["autogroup:admin"]
  }
}
```

This prevents any other machines on the mesh from opening sockets on port 8443.
