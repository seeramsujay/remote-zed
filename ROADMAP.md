# Engineering Roadmap

This roadmap outlines the multi-phase engineering plan for building, testing, and deploying Zed Remote.

---

## Development Milestones

| Milestone | Phase Focus | Key Deliverables | Status |
| :--- | :--- | :--- | :--- |
| **v0.1.0** | Phase 1: Core Proxy Engine | - Rust stdio process wrapper<br>- JSON-RPC ACP frame deserializer<br>- Append-only session logger (`.jsonl`) | Completed |
| **v0.2.0** | Phase 2: Gateway & Git Integration | - Encrypted WebSocket server over Tailscale<br>- Native Git commit/push engine (`git2` crate)<br>- Token auth handshake | Completed |
| **v0.3.0** | Phase 3: Mobile Client (Flutter) | - Dual-panel mobile layout<br>- Real-time streaming markdown renderer<br>- Interactive tool authorization dialogs | Completed |
| **v0.4.0** | Phase 4: State Recovery & Hardening | - Session resumption & event replay engine<br>- Multi-client write-mutex lock<br>- Host telemetry bar (Battery, CPU, Memory) | Completed |

---

## Detailed Phase Breakdown

### Phase 1: Core Stdio Proxying & Logging
- Build `zed-remote-daemon` CLI binary in Rust using `tokio`.
- Implement transparent process spawning to launch target agents (e.g., AntiGravity).
- Intercept and log bidirectional `stdin`/`stdout` JSON-RPC ACP frames.
- Persist session updates to rolling `.jsonl` files for session recovery.

### Phase 2: Secure Tunneling & Git Operations
- Implement a `tokio-tungstenite` WebSocket server bound to private network interfaces.
- Configure TLS encryption using `rustls` with pre-shared JWT validation.
- Integrate local Git management endpoints using the Rust `git2` bindings:
  - `/git/status`
  - `/git/stage`
  - `/git/commit`
  - `/git/push`

### Phase 3: Flutter Mobile Application
- Implement `acp_dart` package bindings to parse ACP JSON-RPC payloads into Dart state models.
- Build the **Agent Panel**:
  - Token-by-token streaming response views.
  - Collapsible cards for reasoning thoughts and tool execution logs.
  - Pop-up authorization modals for `session/request_permission` events.
- Build the **Repository Panel**:
  - Interactive file list with modified lines indicator.
  - Structural diff previews.
  - Commit message text entry and one-tap Git push.

### Phase 4: Resilience & Edge Cases
- Handle mobile network dropouts with automatic reconnection retry logic.
- Implement session replay (`session/load`) upon reconnecting.
- Implement conflict resolution (single-writer lock) when prompts are entered in both Zed and mobile simultaneously.
