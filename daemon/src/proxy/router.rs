//! Bidirectional message router coordinating Zed stdio, agent subprocess, and mobile clients.

use crate::error::Result;
use crate::protocol::{error_codes, format_ndjson_line, JsonRpcMessage, JsonRpcResponse, RequestId};
use crate::security::SecurityGuard;
use crate::session::{MessageDirection, SessionManager};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{broadcast, mpsc, Mutex, RwLock};
use tracing::{debug, error, info, warn};

/// Tracks pending permission requests awaiting user decision.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PendingPermission {
    pub session_id: String,
    pub tool_call_id: String,
    pub tool_name: String,
    pub title: String,
    pub raw_input: serde_json::Value,
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
    /// Active operational mode (e.g. "yolo", "auto", "plan").
    current_mode: Arc<RwLock<String>>,
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
            current_mode: Arc::new(RwLock::new("yolo".to_string())),
        }
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
            if v.tool_call_id == tool_call_id || k == tool_call_id {
                Some(k.clone())
            } else {
                None
            }
        });

        if let Some(key) = found_key {
            if let Some(pending) = perms.remove(&key) {
                let is_allow = !option_id.starts_with("deny")
                    && !option_id.starts_with("reject")
                    && option_id != "cancel";
                let decision_str = if is_allow { "approved" } else { "rejected" };

                info!(
                    "Resolving tool permission approval for '{}' (tool '{}') -> {}",
                    pending.tool_call_id, pending.tool_name, decision_str
                );

                let resp_frame = serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": pending.request_id,
                    "result": {
                        "decision": decision_str,
                        "outcome": {
                            "outcome": decision_str
                        }
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
                            self.session_manager
                                .log_event(session_id, MessageDirection::AgentToZed, &serde_json::to_value(notif).unwrap_or_default())
                                .await;

                            // Check if turn finished to release writer lock
                            if let Some(update_type) = notif.params.get("update")
                                .and_then(|u| u.get("sessionUpdateType"))
                                .and_then(|t| t.as_str())
                            {
                                if update_type == "turn_completed" {
                                    self.session_manager.release_prompt_lock(session_id).await;
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

                        let mode = self.current_mode.read().await.clone();
                        if mode == "yolo" {
                            info!(
                                "YOLO mode active: auto-approving subprocess/tool permission {:?} for tool '{}' ({}) in session {}",
                                req.id, tool_name, tool_call_id, session_id
                            );

                            let approval_reply = serde_json::json!({
                                "jsonrpc": "2.0",
                                "id": req.id,
                                "result": {
                                    "decision": "approved",
                                    "outcome": {
                                        "outcome": "approved"
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

                        let mut perms = self.pending_permissions.lock().await;
                        perms.insert(
                            tool_call_id.clone(),
                            PendingPermission {
                                session_id: session_id.clone(),
                                tool_call_id,
                                tool_name,
                                title,
                                raw_input,
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
                _ => {}
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
                        let session_id = req.params.get("sessionId")
                            .and_then(|v| v.as_str())
                            .unwrap_or("default");

                        // Concurrency check: enforce single-writer lock
                        if let Err(e) = self.session_manager.acquire_prompt_lock(session_id).await {
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
                            .log_event(session_id, MessageDirection::MobileToAgent, &serde_json::to_value(&req).unwrap_or_default())
                            .await;

                        // Forward prompt to agent stdin
                        if let Err(e) = self.agent_stdin_tx.send(format_ndjson_line(trimmed)).await {
                            error!("Failed to route mobile prompt to agent: {}", e);
                            self.session_manager.release_prompt_lock(session_id).await;
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
                                serde_json::json!({ "status": "dispatched" }),
                            ))
                            .unwrap_or_default(),
                        )
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
