//! Bidirectional message router coordinating Zed stdio, agent subprocess, and mobile clients.

use crate::error::Result;
use crate::protocol::{error_codes, format_ndjson_line, JsonRpcMessage, JsonRpcResponse, RequestId};
use crate::security::SecurityGuard;
use crate::session::{MessageDirection, SessionManager};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{broadcast, mpsc, Mutex};
use tracing::{debug, error, info, warn};

/// Tracks pending permission requests awaiting user decision.
#[derive(Debug, Clone)]
pub struct PendingPermission {
    pub session_id: String,
    pub tool_call_id: String,
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
    /// Map of pending permission requests indexed by request ID string.
    pending_permissions: Arc<Mutex<HashMap<String, PendingPermission>>>,
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
        }
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
                        if let Some(session_id) = req.params.get("sessionId").and_then(|v| v.as_str()) {
                            let id_str = format!("{:?}", req.id);
                            let mut perms = self.pending_permissions.lock().await;
                            perms.insert(
                                id_str,
                                PendingPermission {
                                    session_id: session_id.to_string(),
                                    tool_call_id: req.params.get("toolCall")
                                        .and_then(|t| t.get("toolCallId"))
                                        .and_then(|i| i.as_str())
                                        .unwrap_or_default()
                                        .to_string(),
                                    request_id: req.id.clone(),
                                },
                            );
                            self.session_manager
                                .log_event(session_id, MessageDirection::AgentToZed, &serde_json::to_value(req).unwrap_or_default())
                                .await;
                        }
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
                if let Some(pending) = perms.remove(&id_str) {
                    info!(
                        "Mobile resolved permission request {:?} for session {}",
                        res.id, pending.session_id
                    );

                    self.session_manager
                        .log_event(&pending.session_id, MessageDirection::MobileToAgent, &serde_json::to_value(&res).unwrap_or_default())
                        .await;

                    // Forward permission decision to agent child stdin
                    let _ = self.agent_stdin_tx.send(format_ndjson_line(trimmed)).await;

                    // Also mirror decision to Zed stdout so desktop UI unblocks
                    let _ = self.zed_stdout_tx.send(format_ndjson_line(trimmed)).await;
                }
                None
            }
            JsonRpcMessage::Notification(_) => None,
        }
    }
}
