# Protocol Specification: Zed Remote JSON-RPC 2.0 & ACP

Zed Remote operates over two integrated protocol layers:
1. **Agent Client Protocol (ACP)**: Standardized JSON-RPC 2.0 messages exchanged between Zed, the daemon proxy, and the target agent.
2. **Zed Remote Extension RPC**: Daemon management endpoints for Git, interactive terminal, filesystem browsing, session replay, and host telemetry.

---

## 1. ACP Core Frames

All frames are formatted as Newline-Delimited JSON (NDJSON) over stdio and standard JSON text frames over WebSockets.

### `initialize` (Request)

Client requests connection capabilities from the agent.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": 1,
    "clientCapabilities": {
      "fs": {
        "readTextFile": true,
        "writeTextFile": true
      },
      "terminal": true
    }
  }
}
```

### `session/prompt` (Request)

Submitted by Zed or mobile client to dispatch instructions to the AI agent.

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "session/prompt",
  "params": {
    "sessionId": "sess_default_01",
    "prompt": "Refactor the auth middleware to support bearer tokens"
  }
}
```

### `session/update` (Notification)

Streamed by the agent to report progress, thought chunks, and generated message tokens.

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_default_01",
    "update": {
      "sessionUpdateType": "agent_message_chunk",
      "content": {
        "type": "text",
        "text": "Refactoring src/middleware/auth.rs..."
      }
    }
  }
}
```

### `session/request_permission` (Request)

Emitted by the agent when requesting execution approval for terminal commands or file changes.

```json
{
  "jsonrpc": "2.0",
  "id": 105,
  "method": "session/request_permission",
  "params": {
    "sessionId": "sess_default_01",
    "toolCall": {
      "toolCallId": "call_exec_902",
      "name": "terminal/create",
      "parameters": {
        "command": "cargo test --workspace"
      }
    }
  }
}
```

### Permission Response (Result)

```json
{
  "jsonrpc": "2.0",
  "id": 105,
  "result": {
    "decision": "approved"
  }
}
```

---

## 2. Daemon Extension Endpoints

### `/session/load` (Request)

Replays recorded session logs to reconnecting mobile clients.

```json
{
  "jsonrpc": "2.0",
  "id": 300,
  "method": "session/load",
  "params": {
    "sessionId": "sess_default_01",
    "fromSequence": 0
  }
}
```

### `/git/status` (Request)

Queries working directory git status and modified files.

```json
{
  "jsonrpc": "2.0",
  "id": 401,
  "method": "git/status",
  "params": {}
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 401,
  "result": {
    "branch": "main",
    "clean": false,
    "files": [
      {
        "path": "src/gateway/server.rs",
        "status": "modified",
        "staged": false,
        "insertions": 14,
        "deletions": 2
      }
    ]
  }
}
```

### `/git/commit` (Request)

Stages all modified files and commits with the supplied message.

```json
{
  "jsonrpc": "2.0",
  "id": 402,
  "method": "git/commit",
  "params": {
    "message": "feat(gateway): add token validation and heartbeat ping",
    "stageAll": true
  }
}
```

### `/git/push` (Request)

Pushes committed changes to configured remote.

```json
{
  "jsonrpc": "2.0",
  "id": 403,
  "method": "git/push",
  "params": {
    "remote": "origin",
    "branch": "main"
  }
}
```

### `/terminal/exec` (Request)

Executes an interactive shell command within the active directory buffer.

```json
{
  "jsonrpc": "2.0",
  "id": 601,
  "method": "terminal/exec",
  "params": {
    "command": "mkdir -p my-new-project && cd my-new-project"
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 601,
  "result": {
    "stdout": "",
    "stderr": "",
    "exit_code": 0,
    "cwd": "/home/username/Projects/my-new-project"
  }
}
```

### `/fs/list` (Request)

Lists files and directories for a given path.

```json
{
  "jsonrpc": "2.0",
  "id": 602,
  "method": "fs/list",
  "params": {
    "path": "/home/username/Projects"
  }
}
```

### `/fs/mkdir` (Request)

Creates a directory on the host filesystem.

```json
{
  "jsonrpc": "2.0",
  "id": 603,
  "method": "fs/mkdir",
  "params": {
    "path": "my-app"
  }
}
```

### `/workspace/set` (Request)

Switches the active workspace directory for AI Agent and Git tracking.

```json
{
  "jsonrpc": "2.0",
  "id": 604,
  "method": "workspace/set",
  "params": {
    "path": "/home/username/Projects/my-app"
  }
}
```

### `/system/telemetry` (Request)

Polls hardware metrics from the host machine.

```json
{
  "jsonrpc": "2.0",
  "id": 501,
  "method": "system/telemetry",
  "params": {}
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 501,
  "result": {
    "hostName": "workstation-arch",
    "os": "Linux 6.10.3",
    "cpuUsagePercent": 14.5,
    "memoryUsedBytes": 8589934592,
    "memoryTotalBytes": 33685504000,
    "batteryPercent": 88.0,
    "isCharging": true,
    "uptimeSeconds": 148200
  }
}
```
