//! Bidirectional message router coordinating Zed stdio, agent subprocess, and mobile clients.

use crate::error::Result;
use crate::protocol::{error_codes, format_ndjson_line, JsonRpcMessage, JsonRpcResponse, RequestId};
use crate::security::SecurityGuard;
use crate::session::{MessageDirection, SessionManager};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::{broadcast, mpsc, oneshot, Mutex, RwLock};
use tracing::{debug, error, info, warn};

/// Tracks pending permission requests awaiting user decision.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PendingPermission {
    pub session_id: String,
    pub tool_call_id: String,
    pub tool_name: String,
    pub title: String,
    pub raw_input: serde_json::Value,
    pub options: Vec<serde_json::Value>,
    pub request_id: RequestId,
}

/// Central routing engine bridging Zed stdio, the child agent, and remote mobile clients.
#[derive(Clone)]
pub struct MessageRouter {
    /// Broadcast channel distributing agent updates and tool prompts to connected mobile clients.
    pub mobile_broadcast_tx: broadcast::Sender<String>,
    /// MPSC sender for dispatching NDJSON strings directly to the child agent's stdin.
    agent_stdin_tx: mpsc::Sender<String>,
    /// MPSC sender for dispatching NDJSON strings back to Zed's stdout.
    zed_stdout_tx: mpsc::Sender<String>,
    /// Session tracking and logging engine.
    session_manager: SessionManager,
    /// Security guardrails and command filter.
    security: SecurityGuard,
    /// Map of pending permission requests indexed by tool call ID or request ID string.
    pending_permissions: Arc<Mutex<HashMap<String, PendingPermission>>>,
    /// Map of pending requests dispatched to the child agent awaiting a direct response.
    pending_agent_requests: Arc<Mutex<HashMap<String, oneshot::Sender<serde_json::Value>>>>,
    /// Active operational mode (e.g. "yolo", "auto", "plan").
    current_mode: Arc<RwLock<String>>,
    /// Actively tracked session ID in flight between Zed and the agent.
    pub active_session_id: Arc<RwLock<Option<String>>>,
}

impl MessageRouter {
    /// Initializes a new message router.
    pub fn new(
        mobile_broadcast_tx: broadcast::Sender<String>,
        agent_stdin_tx: mpsc::Sender<String>,
        zed_stdout_tx: mpsc::Sender<String>,
        session_manager: SessionManager,
        security: SecurityGuard,
    ) -> Self {
        Self {
            mobile_broadcast_tx,
            agent_stdin_tx,
            zed_stdout_tx,
            session_manager,
            security,
            pending_permissions: Arc::new(Mutex::new(HashMap::new())),
            pending_agent_requests: Arc::new(Mutex::new(HashMap::new())),
            current_mode: Arc::new(RwLock::new("yolo".to_string())),
            active_session_id: Arc::new(RwLock::new(None)),
        }
    }

    /// Retrieves the active session ID, falling back to the newest discovered session log.
    pub async fn get_active_session_id(&self) -> Option<String> {
        let current = self.active_session_id.read().await.clone();
        if current.is_some() {
            return current;
        }
        let discovered = self.session_manager.get_latest_session_id().await;
        if discovered.is_some() {
            let mut write_lock = self.active_session_id.write().await;
            *write_lock = discovered.clone();
        }
        discovered
    }

    /// Sets or updates the active session ID.
    pub async fn set_active_session_id(&self, session_id: &str) {
        if !session_id.is_empty() && session_id != "default" && session_id != "main-thread" {
            let mut write_lock = self.active_session_id.write().await;
            *write_lock = Some(session_id.to_string());
        }
    }

    /// Dispatches a raw line directly to Zed stdout so the desktop UI updates.
    pub async fn send_to_zed_stdout(&self, line: &str) -> Result<()> {
        self.zed_stdout_tx
            .send(format_ndjson_line(line))
            .await
            .map_err(|e| crate::error::DaemonError::Internal(format!("Failed to send to Zed stdout: {}", e)))
    }

    /// Dispatches a request to the child agent and waits asynchronously for its matching response.
    pub async fn dispatch_agent_request(&self, method: &str, params: serde_json::Value) -> std::result::Result<serde_json::Value, String> {
        let req_id = format!("router-{}", uuid::Uuid::new_v4());
        let (tx, rx) = oneshot::channel();
        {
            let mut pending = self.pending_agent_requests.lock().await;
            pending.insert(req_id.clone(), tx);
        }

        let rpc_msg = serde_json::json!({
            "jsonrpc": "2.0",
            "id": req_id,
            "method": method,
            "params": params
        }).to_string();

        if let Err(e) = self.agent_stdin_tx.send(format_ndjson_line(&rpc_msg)).await {
            let mut pending = self.pending_agent_requests.lock().await;
            pending.remove(&req_id);
            return Err(format!("Failed to send to agent stdin: {}", e));
        }

        match tokio::time::timeout(std::time::Duration::from_secs(5), rx).await {
            Ok(Ok(val)) => Ok(val),
            Ok(Err(_)) => Err("Agent dropped request channel".to_string()),
            Err(_) => {
                let mut pending = self.pending_agent_requests.lock().await;
                pending.remove(&req_id);
                Err("Agent request timed out after 5s".to_string())
            }
        }
    }

    /// Dispatches an out-of-band push notification to the user's mobile device via Bunker ntfy topics.
    pub fn trigger_bunker_ntfy(title: &str, body: &str, tags: &str, priority: &str) {
        let title_owned = title.to_string();
        let body_owned = body.to_string();
        let tags_owned = tags.to_string();
        let prio_owned = priority.to_string();
        tokio::spawn(async move {
            let home = match std::env::var("HOME") {
                Ok(h) => h,
                Err(_) => return,
            };
            let candidates = [
                std::path::Path::new(&home).join(".config/zed-remote/bunker-session.json"),
                std::path::Path::new(&home).join(".zed-remote/bunker.json"),
            ];
            let mut found_topics: Vec<(std::time::SystemTime, String)> = Vec::new();
            for bunker_path in &candidates {
                if bunker_path.exists() {
                    let mtime = match tokio::fs::metadata(bunker_path).await {
                        Ok(meta) => meta.modified().unwrap_or(std::time::SystemTime::UNIX_EPOCH),
                        Err(_) => std::time::SystemTime::UNIX_EPOCH,
                    };
                    if let Ok(content) = tokio::fs::read_to_string(bunker_path).await {
                        if let Ok(json_val) = serde_json::from_str::<serde_json::Value>(&content) {
                            if let Some(t) = json_val.get("ntfy_topic").and_then(|t| t.as_str()) {
                                found_topics.push((mtime, t.to_string()));
                            }
                        }
                    }
                }
            }
            found_topics.sort_by(|a, b| b.0.cmp(&a.0));
            let topic = match found_topics.into_iter().next() {
                Some((_, t)) => t,
                None => return,
            };

            let servers = ["https://ntfy.sh", "https://ntfy.adminforge.de", "https://ntfy.tedomum.fr"];
            for srv in servers {
                let url = format!("{}/{}", srv, topic);
                let _ = tokio::process::Command::new("curl")
                    .args([
                        "-fsSL",
                        "--max-time", "5",
                        "--connect-timeout", "2",
                        "-X", "POST",
                        "-H", &format!("Title: {}", title_owned),
                        "-H", &format!("Priority: {}", prio_owned),
                        "-H", &format!("Tags: {}", tags_owned),
                        "-d", &body_owned,
                        &url,
                    ])
                    .output()
                    .await;
            }
        });
    }

    /// Returns the currently active operational mode (e.g. "yolo", "auto", "plan").
    pub async fn get_mode(&self) -> String {
        self.current_mode.read().await.clone()
    }

    /// Sets the active operational mode.
    pub async fn set_mode(&self, mode: &str) {
        let mut lock = self.current_mode.write().await;
        *lock = mode.to_string();
        info!("Updated message router operational mode to: '{}'", mode);
    }

    /// Retrieves all pending tool permission approvals formatted for the mobile HTTP API.
    pub async fn get_pending_approvals(&self) -> Vec<serde_json::Value> {
        let perms = self.pending_permissions.lock().await;
        perms
            .values()
            .map(|p| {
                serde_json::json!({
                    "tool_call_id": p.tool_call_id,
                    "title": p.title,
                    "tool_name": p.tool_name,
                    "content": [],
                    "raw_input": p.raw_input,
                    "allow_once_available": true,
                    "deny_once_available": true,
                    "kind": "permission",
                    "options": [
                        {
                            "option_id": "allow_once",
                            "label": "Allow",
                            "kind": "allow_once",
                            "enabled": true
                        },
                        {
                            "option_id": "allow_always",
                            "label": "Allow Always",
                            "kind": "allow_always",
                            "enabled": true
                        },
                        {
                            "option_id": "deny_once",
                            "label": "Deny",
                            "kind": "reject_once",
                            "enabled": true
                        }
                    ],
                    "patterns": []
                })
            })
            .collect()
    }

    /// Resolves a pending tool permission approval by tool call ID and dispatches the decision.
    pub async fn resolve_approval(&self, tool_call_id: &str, option_id: &str) -> bool {
        let mut perms = self.pending_permissions.lock().await;
        let found_key = perms.iter().find_map(|(k, v)| {
            if v.tool_call_id == tool_call_id || k == tool_call_id || k.ends_with(&format!(":{}", tool_call_id)) {
                Some(k.clone())
            } else {
                None
            }
        });

        if let Some(key) = found_key {
            if let Some(pending) = perms.remove(&key) {
                let is_cancel = option_id == "cancel";
                let is_allow = !option_id.starts_with("deny")
                    && !option_id.starts_with("reject")
                    && !is_cancel;
                let decision_str = if is_allow { "approved" } else { "rejected" };

                info!(
                    "Resolving tool permission approval for '{}' (tool '{}') -> {}",
                    pending.tool_call_id, pending.tool_name, decision_str
                );

                let outcome = if is_cancel {
                    serde_json::json!({ "outcome": "cancelled" })
                } else if is_allow {
                    let matched_id = pending.options.iter()
                        .find(|o| o.get("optionId").and_then(|v| v.as_str()) == Some(option_id))
                        .and_then(|o| o.get("optionId").and_then(|v| v.as_str()))
                        .or_else(|| {
                            pending.options.iter()
                                .find(|o| {
                                    let opt = o.get("optionId").and_then(|v| v.as_str()).unwrap_or("");
                                    let kind = o.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                                    opt.contains("allow") || kind.contains("allow")
                                })
                                .and_then(|o| o.get("optionId").and_then(|v| v.as_str()))
                        })
                        .unwrap_or("allow_once");
                    serde_json::json!({ "outcome": "selected", "optionId": matched_id })
                } else {
                    let matched_id = pending.options.iter()
                        .find(|o| o.get("optionId").and_then(|v| v.as_str()) == Some(option_id))
                        .and_then(|o| o.get("optionId").and_then(|v| v.as_str()))
                        .or_else(|| {
                            pending.options.iter()
                                .find(|o| {
                                    let opt = o.get("optionId").and_then(|v| v.as_str()).unwrap_or("");
                                    let kind = o.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                                    opt.contains("reject") || opt.contains("deny") || kind.contains("reject") || kind.contains("deny")
                                })
                                .and_then(|o| o.get("optionId").and_then(|v| v.as_str()))
                        })
                        .unwrap_or("reject_once");
                    serde_json::json!({ "outcome": "selected", "optionId": matched_id })
                };

                let resp_frame = serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": pending.request_id,
                    "result": {
                        "decision": decision_str,
                        "outcome": outcome
                    }
                })
                .to_string();

                let _ = self.agent_stdin_tx.send(format_ndjson_line(&resp_frame)).await;
                let _ = self.zed_stdout_tx.send(format_ndjson_line(&resp_frame)).await;
                let _ = self.mobile_broadcast_tx.send(resp_frame);
                return true;
            }
        }
        false
    }

    /// Subscribes a new WebSocket mobile client to the broadcast feed.
    pub fn subscribe_mobile(&self) -> broadcast::Receiver<String> {
        self.mobile_broadcast_tx.subscribe()
    }

    /// Handles an incoming raw message string received from Zed's standard input.
    pub async fn handle_zed_input(&self, line: &str) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return;
        }

        debug!("Zed -> Proxy: {}", trimmed);

        if let Ok(msg) = JsonRpcMessage::parse(trimmed) {
            match &msg {
                JsonRpcMessage::Request(req) => {
                    if let Some(session_id) = req.params.get("sessionId").or_else(|| req.params.get("session_id")).and_then(|v| v.as_str()) {
                        self.set_active_session_id(session_id).await;
                    }
                    if req.method == "session/prompt" {
                        if let Some(session_id) = req.params.get("sessionId").and_then(|v| v.as_str()) {
                            let _ = self.session_manager.acquire_prompt_lock(session_id).await;
                            self.session_manager
                                .log_event(session_id, MessageDirection::ZedToAgent, &serde_json::to_value(req).unwrap_or_default())
                                .await;
                        }
                    }
                }
                JsonRpcMessage::Response(res) => {
                    // Look up and remove matching pending permission entry when resolved by desktop response
                    let mut perms = self.pending_permissions.lock().await;
                    let found_id = perms
                        .iter()
                        .find(|(_, p)| p.request_id == res.id)
                        .map(|(k, _)| k.clone());
                    if let Some(tool_call_id) = found_id {
                        perms.remove(&tool_call_id);
                        info!("Removed pending permission {} resolved by desktop response id {:?}", tool_call_id, res.id);
                    }
                }
                _ => {}
            }
        }

        // Forward to child agent stdin
        if let Err(e) = self.agent_stdin_tx.send(format_ndjson_line(trimmed)).await {
            error!("Failed to forward Zed message to agent stdin: {}", e);
        }
    }

    /// Handles an incoming raw message string received from the child agent's standard output.
    pub async fn handle_agent_output(&self, line: &str) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return;
        }

        debug!("Agent -> Proxy: {}", trimmed);

        if let Ok(msg) = JsonRpcMessage::parse(trimmed) {
            match &msg {
                JsonRpcMessage::Notification(notif) => {
                    if notif.method == "session/update" {
                        if let Some(session_id) = notif.params.get("sessionId").and_then(|v| v.as_str()) {
                            self.set_active_session_id(session_id).await;
                            self.session_manager
                                .log_event(session_id, MessageDirection::AgentToZed, &serde_json::to_value(notif).unwrap_or_default())
                                .await;

                            // Check if turn finished to release writer lock
                            if let Some(update_type) = notif.params.get("update")
                                .and_then(|u| u.get("sessionUpdateType").or_else(|| u.get("sessionUpdate")))
                                .and_then(|t| t.as_str())
                            {
                                if update_type == "turn_completed" {
                                    self.session_manager.release_prompt_lock(session_id).await;
                                    // Broadcast completion SSE to mobile clients
                                    let completion_sse = format!(
                                        "event: thread_completed\ndata: {}\n\n",
                                        serde_json::json!({
                                            "project_id": "current-project",
                                            "project_name": "remote-zed",
                                            "thread_id": session_id,
                                            "thread_title": "AntiGravity Turn Completed",
                                            "turn_id": format!("turn-{}", uuid::Uuid::new_v4())
                                        })
                                    );
                                    let _ = self.mobile_broadcast_tx.send(completion_sse);
                                    Self::trigger_bunker_ntfy("AntiGravity Task Finished", "Turn completed on remote-zed", "robot,check", "default");
                                }
                            }
                        }
                    }
                }
                JsonRpcMessage::Request(req) => {
                    if req.method == "session/request_permission" {
                        let session_id = req
                            .params
                            .get("sessionId")
                            .or_else(|| req.params.get("session_id"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("default")
                            .to_string();

                        self.set_active_session_id(&session_id).await;

                        let tool_call = req.params.get("toolCall").or_else(|| req.params.get("tool_call"));
                        let tool_call_id = tool_call
                            .and_then(|t| t.get("toolCallId").or_else(|| t.get("tool_call_id")))
                            .and_then(|i| i.as_str())
                            .unwrap_or_default()
                            .to_string();
                        let tool_name = tool_call
                            .and_then(|t| t.get("name").or_else(|| t.get("tool_name")))
                            .and_then(|n| n.as_str())
                            .unwrap_or("terminal/exec")
                            .to_string();
                        let title = tool_call
                            .and_then(|t| t.get("title"))
                            .and_then(|t| t.as_str())
                            .unwrap_or_else(|| {
                                if tool_name.contains("terminal") || tool_name.contains("exec") {
                                    "Execute shell command"
                                } else {
                                    "Tool execution permission"
                                }
                            })
                            .to_string();
                        let raw_input = tool_call
                            .and_then(|t| {
                                t.get("parameters")
                                    .or_else(|| t.get("raw_input"))
                                    .or_else(|| t.get("rawInput"))
                            })
                            .cloned()
                            .unwrap_or(serde_json::Value::Null);

                        let options: Vec<serde_json::Value> = req
                            .params
                            .get("options")
                            .and_then(|o| o.as_array())
                            .cloned()
                            .unwrap_or_default();

                        // Broadcast question/approval SSE event to mobile clients
                        let question_sse = format!(
                            "event: thread_question\ndata: {}\n\n",
                            serde_json::json!({
                                "project_id": "current-project",
                                "project_name": "remote-zed",
                                "thread_id": session_id,
                                "thread_title": format!("Approval required: {}", tool_name),
                                "turn_id": tool_call_id
                            })
                        );
                        let _ = self.mobile_broadcast_tx.send(question_sse);

                        let mode = self.current_mode.read().await.clone();
                        if mode == "yolo" {
                            info!(
                                "YOLO mode active: auto-approving subprocess/tool permission {:?} for tool '{}' ({}) in session {}",
                                req.id, tool_name, tool_call_id, session_id
                            );

                            let default_allow_option = options
                                .iter()
                                .find(|o| {
                                    let opt_id = o.get("optionId").and_then(|v| v.as_str()).unwrap_or("");
                                    let kind = o.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                                    opt_id.contains("allow") || kind.contains("allow")
                                })
                                .and_then(|o| o.get("optionId").and_then(|v| v.as_str()))
                                .unwrap_or("allow_once");

                            let approval_reply = serde_json::json!({
                                "jsonrpc": "2.0",
                                "id": req.id,
                                "result": {
                                    "decision": "approved",
                                    "outcome": {
                                        "outcome": "selected",
                                        "optionId": default_allow_option
                                    }
                                }
                            })
                            .to_string();

                            // Unblock child agent immediately
                            if let Err(e) = self.agent_stdin_tx.send(format_ndjson_line(&approval_reply)).await {
                                error!("Failed to send auto-approval to agent stdin: {}", e);
                            }

                            // Mirror auto-approval to Zed stdout and mobile broadcast
                            let _ = self.zed_stdout_tx.send(format_ndjson_line(&approval_reply)).await;
                            let _ = self.mobile_broadcast_tx.send(approval_reply);

                            self.session_manager
                                .log_event(
                                    &session_id,
                                    MessageDirection::AgentToZed,
                                    &serde_json::json!({
                                        "method": "session/request_permission_auto_approved",
                                        "tool_call_id": tool_call_id,
                                        "tool_name": tool_name,
                                        "mode": "yolo"
                                    }),
                                )
                                .await;

                            return;
                        }

                        // Send push notification when permission requires interactive user confirmation
                        Self::trigger_bunker_ntfy(
                            "Agent Approval Required",
                            &format!("AntiGravity Agent needs permission: {}", tool_name),
                            "warning,question",
                            "high"
                        );

                        let scoped_key = format!("{}:{}", session_id, tool_call_id);
                        let mut perms = self.pending_permissions.lock().await;
                        perms.insert(
                            scoped_key,
                            PendingPermission {
                                session_id: session_id.clone(),
                                tool_call_id,
                                tool_name,
                                title,
                                raw_input,
                                options,
                                request_id: req.id.clone(),
                            },
                        );
                        self.session_manager
                            .log_event(
                                &session_id,
                                MessageDirection::AgentToZed,
                                &serde_json::to_value(req).unwrap_or_default(),
                            )
                            .await;
                    }
                }
                JsonRpcMessage::Response(res) => {
                    let id_str = match &res.id {
                        RequestId::String(s) => s.clone(),
                        RequestId::Integer(i) => i.to_string(),
                    };
                    let mut pending = self.pending_agent_requests.lock().await;
                    if let Some(tx) = pending.remove(&id_str) {
                        let _ = tx.send(serde_json::to_value(res).unwrap_or_default());
                    }
                }
            }
        }

        // Mirror to Zed stdout
        if let Err(e) = self.zed_stdout_tx.send(format_ndjson_line(trimmed)).await {
            error!("Failed to forward agent output to Zed stdout: {}", e);
        }

        // Broadcast to mobile clients
        let _ = self.mobile_broadcast_tx.send(trimmed.to_string());
    }

    /// Handles an incoming message string originating from a mobile WebSocket client.
    pub async fn handle_mobile_message(&self, text: &str) -> Option<String> {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return None;
        }

        debug!("Mobile -> Proxy: {}", trimmed);

        let msg = match JsonRpcMessage::parse(trimmed) {
            Ok(m) => m,
            Err(e) => {
                warn!("Invalid JSON-RPC from mobile client: {}", e);
                return Some(
                    serde_json::to_string(&JsonRpcResponse::error(
                        RequestId::Integer(0),
                        error_codes::PARSE_ERROR,
                        format!("Parse error: {}", e),
                    ))
                    .unwrap_or_default(),
                );
            }
        };

        match msg {
            JsonRpcMessage::Request(req) => {
                match req.method.as_str() {
                    "session/prompt" => {
                        let raw_session_id = req.params.get("sessionId")
                            .and_then(|v| v.as_str())
                            .unwrap_or("default");

                        let session_id = if raw_session_id == "default" || raw_session_id == "main-thread" {
                            self.get_active_session_id().await.unwrap_or_else(|| "default".to_string())
                        } else {
                            raw_session_id.to_string()
                        };

                        // Rewrite payload with resolved session_id if needed
                        let prompt_payload = if session_id != raw_session_id {
                            let mut new_req = req.clone();
                            if let Some(map) = new_req.params.as_object_mut() {
                                map.insert("sessionId".to_string(), serde_json::Value::String(session_id.clone()));
                            }
                            serde_json::to_string(&new_req).unwrap_or_else(|_| trimmed.to_string())
                        } else {
                            trimmed.to_string()
                        };

                        // Concurrency check: enforce single-writer lock
                        if let Err(e) = self.session_manager.acquire_prompt_lock(&session_id).await {
                            warn!("Concurrent prompt rejected: {}", e);
                            return Some(
                                serde_json::to_string(&JsonRpcResponse::error(
                                    req.id,
                                    error_codes::SERVER_BUSY,
                                    "Server busy: another prompt is currently processing",
                                ))
                                .unwrap_or_default(),
                            );
                        }

                        // Log event
                        self.session_manager
                            .log_event(&session_id, MessageDirection::MobileToAgent, &serde_json::to_value(&req).unwrap_or_default())
                            .await;

                        // Forward prompt to agent stdin
                        if let Err(e) = self.agent_stdin_tx.send(format_ndjson_line(&prompt_payload)).await {
                            error!("Failed to route mobile prompt to agent: {}", e);
                            self.session_manager.release_prompt_lock(&session_id).await;
                            return Some(
                                serde_json::to_string(&JsonRpcResponse::error(
                                    req.id,
                                    error_codes::INTERNAL_ERROR,
                                    "Failed to communicate with agent subprocess",
                                ))
                                .unwrap_or_default(),
                            );
                        }


                        // Acknowledge request receipt to mobile
                        Some(
                            serde_json::to_string(&JsonRpcResponse::success(
                                req.id,
                                serde_json::json!({ "status": "dispatched", "sessionId": session_id }),
                            ))
                            .unwrap_or_default(),
                        )
                    }
                    "session/new" => {
                        match self.dispatch_agent_request("session/new", req.params.clone()).await {
                            Ok(mut res_val) => {
                                if let Some(session_id) = res_val.get("result").and_then(|r| r.get("sessionId")).and_then(|s| s.as_str()) {
                                    self.set_active_session_id(session_id).await;
                                }
                                // Also notify Zed's stdout so desktop tracks the new session
                                let _ = self.send_to_zed_stdout(&res_val.to_string()).await;
                                // Restore original mobile request ID for correlation
                                if let Some(obj) = res_val.as_object_mut() {
                                    obj.insert("id".to_string(), serde_json::to_value(&req.id).unwrap_or(serde_json::Value::Null));
                                }
                                Some(res_val.to_string())
                            }
                            Err(e) => Some(
                                serde_json::to_string(&JsonRpcResponse::error(
                                    req.id,
                                    error_codes::INTERNAL_ERROR,
                                    format!("Failed to create new session: {}", e),
                                ))
                                .unwrap_or_default(),
                            ),
                        }
                    }
                    _ => None,
                }
            }
            JsonRpcMessage::Response(res) => {
                // Check if this response resolves an in-flight permission request
                let id_str = format!("{:?}", res.id);
                let mut perms = self.pending_permissions.lock().await;
                let found_key = perms.iter().find_map(|(k, v)| {
                    if v.request_id == res.id || k == &id_str {
                        Some(k.clone())
                    } else {
                        None
                    }
                });

                if let Some(key) = found_key {
                    if let Some(pending) = perms.remove(&key) {
                        info!(
                            "Mobile resolved permission request {:?} for tool '{}' ({}) in session {}",
                            res.id, pending.tool_name, pending.tool_call_id, pending.session_id
                        );

                        self.session_manager
                            .log_event(
                                &pending.session_id,
                                MessageDirection::MobileToAgent,
                                &serde_json::to_value(&res).unwrap_or_default(),
                            )
                            .await;

                        // Forward permission decision to agent child stdin
                        let _ = self.agent_stdin_tx.send(format_ndjson_line(trimmed)).await;

                        // Also mirror decision to Zed stdout so desktop UI unblocks
                        let _ = self.zed_stdout_tx.send(format_ndjson_line(trimmed)).await;
                    }
                }
                None
            }
            JsonRpcMessage::Notification(_) => None,
        }
    }
}
