# Shared Protocol Definitions

This directory contains the protocol definitions, JSON schemas, and RPC message structures shared between the Rust host daemon (`daemon/`) and the Flutter mobile client (`app/`).

## Protocol Layers

1. **Agent Client Protocol (ACP) (`schemas/acp-schema.json`)**:
   Standardized JSON-RPC 2.0 frames governing interaction between the editor/mobile client and the AI coding agent.
   - Methods: `initialize`, `session/prompt`, `session/update`, `session/request_permission`, `session/cancel`.
   - Update types: `agent_message_chunk`, `agent_thought_chunk`, `tool_call_started`, `tool_call_completed`.

2. **Zed Remote Git Extension RPC (`schemas/git-rpc-schema.json`)**:
   Endpoints exposed by `zed-remote-daemon` allowing mobile users to inspect and operate the host repository out-of-band.
   - Methods: `git/status`, `git/diff`, `git/stage`, `git/commit`, `git/push`.

3. **Host Telemetry & System RPC (`schemas/telemetry-rpc-schema.json`)**:
   Endpoints providing real-time hardware diagnostics and power state control.
   - Methods: `system/telemetry`, `system/power`.

4. **Session Persistence & Replay (`schemas/session-replay-schema.json`)**:
   Format specifications for the append-only `.jsonl` session log files and the `session/load` replay mechanism.
