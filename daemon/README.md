# zed-remote-daemon

The Rust host daemon for Zed Remote. Acts as a transparent stdio proxy between the Zed editor and the target AI agent (e.g. AntiGravity), mirrors ACP streams to a secure WebSocket server over Tailscale, and provides out-of-band Git and host telemetry control.

---

## Architecture

```
[Zed Editor] <---(stdio NDJSON)---> [zed-remote-daemon] <---(stdio NDJSON)---> [Target Agent (AntiGravity)]
                                           |
                                    (WebSocket WSS)
                                           v
                              [Flutter Mobile Application]
```

## CLI Usage

```bash
zed-remote-daemon [OPTIONS]
```

### Options

| Flag | Env Variable | Default | Description |
| --- | --- | --- | --- |
| `--target-command` | `ZED_REMOTE_TARGET_COMMAND` | `antigravity` | Executable path of the target agent |
| `--target-args` | `ZED_REMOTE_TARGET_ARGS` | `acp` | Arguments passed to the target agent |
| `--bind-host` | `ZED_REMOTE_BIND_HOST` | `127.0.0.1` | Network interface IP (e.g. Tailscale `100.x.y.z`) |
| `--port` | `ZED_REMOTE_PORT` | `8443` | WebSocket port |
| `--token-file` | `ZED_REMOTE_TOKEN_FILE` | (none) | File containing secret bearer token |
| `--auth-token` | `ZED_REMOTE_AUTH_TOKEN` | (ephemeral) | Direct authentication token |
| `--session-dir` | `ZED_REMOTE_SESSION_DIR` | `~/.zed-remote/sessions` | Directory storing `.jsonl` session transaction logs |
| `--workspace-root` | `ZED_REMOTE_WORKSPACE_ROOT` | `.` | Root directory of Git workspace |
| `--blocked-commands`| `ZED_REMOTE_BLOCKED_COMMANDS` | `rm -rf /,...` | Comma-separated command blocklist |

---

## Features

- **Transparent Stdio Proxy**: Zero modification required to Zed or the AI agent.
- **Append-only Session Logging**: Transactions written to `.jsonl` for zero data-loss state replay.
- **Single-Writer Mutex**: Prevents race conditions from concurrent prompts on desktop and mobile.
- **Constant-time Auth**: Timing-safe token verification.
- **Integrated Git Engine**: Asynchronous file staging, diff inspection, commit generation, and pushing.
- **Hardware Telemetry**: System CPU, RAM, battery, and power controls.
