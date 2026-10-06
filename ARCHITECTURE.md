# System Architecture

Zed Remote follows a client-proxy-agent layout inspired by headless developer platforms and multi-channel relays like Lunel.

---

## Component Overview

| Component | Tech Stack | Primary Responsibilities |
| :--- | :--- | :--- |
| **Zed Editor** | Rust / GPUI | Desktop code editor; renders native Agent Panel and acts as primary ACP client. |
| **zed-remote-daemon** | Rust / Tokio | Intercepts stdio streams, forwards ACP frames, exposes WebSockets, executes Git tasks. |
| **Target Agent** | Executable CLI | Autonomous coding agent (e.g., AntiGravity) executing logic and code edits. |
| **Mobile Client** | Flutter / Dart | Native mobile interface rendering agent streams and accepting user inputs. |

---

## Communication Architecture

### Protocol Stack

Communication flows across two distinct transport layers:

1. **Desktop IPC Transport**: Communication between Zed, `zed-remote-daemon`, and the target AI agent occurs via standard I/O (`stdin`/`stdout`) using ACP JSON-RPC 2.0 frames.
2. **Network Transport**: Communication between `zed-remote-daemon` and the Mobile Client occurs over encrypted WebSockets (`wss://`) through a private WireGuard/Tailscale mesh network.

```
+-------------------------------------------------------------+
| Desktop Environment                                        |
|                                                             |
| [Zed Editor Client]                                         |
|        ^ (stdin / stdout NDJSON)                            |
|        v                                                    |
| [zed-remote-daemon] <====== (Internal Event Router)         |
|        ^ (child stdin / stdout NDJSON)                      |
|        v                                                    |
| [Target Agent: AntiGravity]                                 |
+-------------------------------------------------------------+
        ^
        | WebSocket (TLS / Tailscale 100.x.y.z:8443)
        v
+-------------------------------------------------------------+
| Mobile Environment                                          |
|                                                             |
| [Flutter App: acp_dart client]                              |
|   - Stream Markdown / Thoughts                              |
|   - Permission Dialogs                                      |
|   - Git Status / Stage / Commit / Push                      |
|   - System Telemetry Monitor                                |
+-------------------------------------------------------------+
```

---

## Detailed Message Flow Sequence

### 1. Agent Initialization & Session Start

1. User opens Zed or activates an agent thread.
2. Zed launches `zed-remote-daemon` as a child process.
3. Daemon launches `antigravity acp` as its own child process.
4. Stdio streams are linked asynchronously via `tokio::process::ChildStdin` and `ChildStdout`.

### 2. Prompt Processing & Dual Streaming

1. User submits a prompt via Zed or Mobile.
2. Daemon receives `session/prompt` JSON-RPC request and routes it to AntiGravity.
3. AntiGravity processes the prompt and streams `session/update` notifications containing agent message chunks and reasoning thoughts.
4. Daemon mirrors these `session/update` notifications to **both** Zed's stdio output and active WebSocket mobile clients.

### 3. Tool Permission Interception

1. AntiGravity attempts to execute a shell command or edit a file, emitting a `session/request_permission` request.
2. Daemon intercepts the request and holds execution pending approval.
3. Daemon pushes a notification frame to the Flutter mobile app.
4. User selects **Approve** on their phone.
5. Mobile app transmits JSON-RPC authorization result back to the daemon, which responds to AntiGravity and unblocks execution.

---

## Session Persistence and Replay Engine

To handle unstable mobile connectivity on cellular networks, the daemon implements an append-only transaction logger:

- Every incoming and outgoing ACP frame is appended to `~/.zed-remote/sessions/<session_id>.jsonl`.
- When a mobile client reconnects after losing signal, it transmits a `session/load` request with the `sessionId`.
- The daemon reads the `.jsonl` log file and replays all missed `session/update` events sequentially, instantly restoring the full conversation state on mobile.

---

## Concurrency and Writer Mutex

To prevent race conditions when prompts are entered concurrently from the desktop editor and mobile phone, the daemon maintains an active session lock:
- Only one active prompt turn is processed per session at any instant.
- Subsequent prompt requests during an ongoing generation return a `-32001 Server Busy` JSON-RPC error.
- Permission requests are uniquely identified by tool call ID and can be fulfilled by either the desktop or authenticated mobile client, unblocking the waiting agent loop.
