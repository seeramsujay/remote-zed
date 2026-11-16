# Zed Remote: Future Roadmap & Automation Architecture

This document tracks upcoming architecture, automation hooks, and planned capabilities for future releases of Zed Remote.

---

## 1. Automation & App Intents (Tasker, MacroDroid, Termux)

Zed Remote will expose native Android App Intents, Broadcast Receivers, and Deep Links to enable powerful automations via Tasker, MacroDroid, and Automate without requiring manual interaction.

### A. Deep Link Schema (`zed://`)
Used for NFC tags, Android shortcuts, widgets, and browser triggers:
- `zed://thread/{thread_id}`: Opens a specific conversation thread.
- `zed://prompt?text={url_encoded_text}&project={project_id}&agent={antigravity|pi}&mode={yolo|auto}`: Automatically starts or continues a prompt turn.
- `zed://workspace?path={remote_path}`: Switches active workspace and terminal root.
- `zed://terminal/exec?command={cmd}`: Executes a remote shell command directly via the encrypted tunnel.

### B. Inbound Broadcast Actions (Commands to Zed Remote)
Tasker or MacroDroid can broadcast intents with extras to control the desktop agent:

1. **`dev.zed.mobile.ACTION_SEND_PROMPT`**
   - **Permission**: `dev.zed.mobile.permission.AUTOMATION` (Signature/Configurable)
   - **Extras**:
     - `extra_prompt` (String, required): The prompt text to deliver to the agent.
     - `extra_thread_id` (String, optional): Target thread UUID or `"main-thread"`.
     - `extra_project_id` (String, optional): Specific project catalog ID.
     - `extra_agent` (String, optional): `"antigravity"` or `"pi"`.
     - `extra_mode` (String, optional): `"yolo"`, `"auto"`, or `"plan"`.
   - **Response Broadcast**: Emits `dev.zed.mobile.EVENT_PROMPT_DISPATCHED` with status.

2. **`dev.zed.mobile.ACTION_CANCEL_TURN`**
   - **Extras**:
     - `extra_thread_id` (String, optional): Defaults to active thread.

3. **`dev.zed.mobile.ACTION_TERMINAL_RUN`**
   - **Extras**:
     - `extra_command` (String, required): Shell command line to execute.
     - `extra_cwd` (String, optional): Working directory.

4. **`dev.zed.mobile.ACTION_RESOLVE_PERMISSION`**
   - **Extras**:
     - `extra_tool_call_id` (String, required): Tool approval identifier.
     - `extra_decision` (String, required): `"allow_once"`, `"allow_always"`, or `"deny"`.

### C. Outbound Broadcast Events (Triggers for Tasker / MacroDroid)
`GatewayEventService` will broadcast events whenever desktop agent milestones occur:

1. **`dev.zed.mobile.EVENT_TURN_COMPLETED`**
   - Triggered when an AI Agent turn finishes.
   - **Extras**:
     - `project_name` (String): e.g. `"remote-zed"`
     - `thread_title` (String): e.g. `"Troubleshooting Zed Tunnel"`
     - `turn_id` (String): Turn UUID
     - `status` (String): `"completed"` | `"failed"`
     - `summary` (String): Short text snippet of the agent's concluding message.

2. **`dev.zed.mobile.EVENT_PERMISSION_REQUESTED`**
   - Triggered when the agent needs permission to execute a tool or command (in non-YOLO modes).
   - **Extras**:
     - `project_name` (String)
     - `tool_name` (String): e.g. `"terminal/exec"`
     - `tool_call_id` (String)
     - `raw_input` (String): Exact command line or file modification requested.
   - **Tasker Use Case**: Auto-approve safe build commands based on regex rules from Tasker.

3. **`dev.zed.mobile.EVENT_TUNNEL_STATE_CHANGED`**
   - Triggered when reverse tunnel or Bunker rendezvous reconnects or rotates.
   - **Extras**:
     - `state` (String): `"connected"`, `"reconnecting"`, `"disconnected"`
     - `latency_ms` (Long)

---

## 2. Full PTY Streaming Terminal Engine
- Transition from command-response execution (`/v2/terminal/exec`) to a full pseudo-terminal (PTY) emulation stream (`/v2/terminal/pty`) using `portable-pty` on Rust.
- WebSocket streaming of ANSI escape sequences and VT100 control codes.
- Direct integration with Android Termux style gesture scrolling, pinch-to-zoom font sizing, and full tmux support.

---

## 3. Wear OS Quick Companion
- Micro-app for Galaxy Watch / Pixel Watch:
  - View running turn progress (Thinking / Tool Execution).
  - One-tap "Allow" / "Deny" notification action buttons for tool permission requests.
  - Quick voice-to-prompt dispatch from smartwatch microphone.

---

## 4. Multi-Workspace Tab Switching
- Tab bar at the top of the mobile screen allowing instantaneous switching between active open Zed workspaces on the host machine.
- Per-workspace thread filters and split terminal instances.
