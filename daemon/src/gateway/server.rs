//! Asynchronous WebSocket server managing mobile client connections, terminal, and extension RPCs.

use crate::error::Result;
use crate::gateway::auth::AuthValidator;
use crate::git::GitEngine;
use crate::protocol::{error_codes, JsonRpcMessage, JsonRpcRequest, JsonRpcResponse, RequestId};
use crate::proxy::MessageRouter;
use crate::session::SessionManager;
use crate::telemetry::{PowerAction, TelemetryCollector};
use crate::terminal::TerminalManager;
use futures_util::{SinkExt, StreamExt};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::accept_hdr_async;
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, error, info, warn};

/// Orchestrates the mobile WebSocket gateway.
pub struct WebSocketGateway {
    bind_addr: SocketAddr,
    auth: AuthValidator,
    router: MessageRouter,
    session_manager: SessionManager,
    git: GitEngine,
    telemetry: Arc<TelemetryCollector>,
    terminal: Arc<TerminalManager>,
}

impl WebSocketGateway {
    /// Creates a new WebSocket gateway instance.
    pub fn new(
        bind_addr: SocketAddr,
        auth: AuthValidator,
        router: MessageRouter,
        session_manager: SessionManager,
        git: GitEngine,
        telemetry: Arc<TelemetryCollector>,
        terminal: Arc<TerminalManager>,
    ) -> Self {
        Self {
            bind_addr,
            auth,
            router,
            session_manager,
            git,
            telemetry,
            terminal,
        }
    }

    /// Starts listening for incoming mobile client connections.
    pub async fn run(&self) -> Result<()> {
        let listener = TcpListener::bind(self.bind_addr).await?;
        info!("WebSocket gateway listening on ws://{}", self.bind_addr);

        loop {
            match listener.accept().await {
                Ok((stream, peer_addr)) => {
                    info!("Incoming connection from {}", peer_addr);
                    let auth = self.auth.clone();
                    let router = self.router.clone();
                    let session_manager = self.session_manager.clone();
                    let git = self.git.clone();
                    let telemetry = Arc::clone(&self.telemetry);
                    let terminal = Arc::clone(&self.terminal);

                    tokio::spawn(async move {
                        if let Err(e) = Self::handle_connection(
                            stream,
                            peer_addr,
                            auth,
                            router,
                            session_manager,
                            git,
                            telemetry,
                            terminal,
                        )
                        .await
                        {
                            warn!("Connection error with {}: {}", peer_addr, e);
                        }
                    });
                }
                Err(e) => {
                    error!("Error accepting TCP connection: {}", e);
                }
            }
        }
    }

    /// Performs the WebSocket handshake with authentication verification, then services client messages.
    async fn handle_connection(
        stream: TcpStream,
        peer_addr: SocketAddr,
        auth: AuthValidator,
        router: MessageRouter,
        session_manager: SessionManager,
        git: GitEngine,
        telemetry: Arc<TelemetryCollector>,
        terminal: Arc<TerminalManager>,
    ) -> Result<()> {
        let mut authenticated = false;

        let callback = |req: &Request, resp: Response| {
            // Check Authorization header first
            if let Some(auth_val) = req.headers().get("Authorization").and_then(|h| h.to_str().ok()) {
                if let Some(token) = AuthValidator::extract_bearer_token(auth_val) {
                    if auth.validate(token) {
                        authenticated = true;
                    }
                }
            }

            // Check query param (?token=xyz)
            if !authenticated {
                if let Some(query) = req.uri().query() {
                    for param in query.split('&') {
                        let mut kv = param.split('=');
                        if let (Some(k), Some(v)) = (kv.next(), kv.next()) {
                            if k == "token" && auth.validate(v) {
                                authenticated = true;
                                break;
                            }
                        }
                    }
                }
            }

            Ok(resp)
        };

        let ws_stream = accept_hdr_async(stream, callback).await?;

        if !authenticated {
            warn!("Rejecting unauthenticated connection from {}", peer_addr);
            return Ok(());
        }

        info!("Authenticated mobile client connected from {}", peer_addr);
        let (mut ws_sender, mut ws_receiver) = ws_stream.split();
        let mut broadcast_rx = router.subscribe_mobile();

        // Spawn outgoing broadcast forwarder
        let send_task = tokio::spawn(async move {
            while let Ok(msg) = broadcast_rx.recv().await {
                if let Err(e) = ws_sender.send(Message::Text(msg)).await {
                    debug!("Failed to send to mobile WS client: {}", e);
                    break;
                }
            }
        });

        // Process incoming client frames
        while let Some(msg_res) = ws_receiver.next().await {
            match msg_res {
                Ok(Message::Text(text)) => {
                    // Check if it's an extension endpoint (git, telemetry, terminal, fs, session/load)
                    if let Ok(JsonRpcMessage::Request(req)) = JsonRpcMessage::parse(&text) {
                        if let Some(extension_resp) = Self::handle_extension_rpc(
                            &req,
                            &session_manager,
                            &git,
                            &telemetry,
                            &terminal,
                        )
                        .await
                        {
                            let _ = router.mobile_broadcast_tx.send(extension_resp);
                            continue;
                        }
                    }

                    // Otherwise route standard ACP frames
                    if let Some(reply) = router.handle_mobile_message(&text).await {
                        let _ = router.mobile_broadcast_tx.send(reply);
                    }
                }
                Ok(Message::Close(_)) => {
                    info!("Client {} requested close", peer_addr);
                    break;
                }
                Ok(Message::Ping(_)) => {}
                Ok(_) => {}
                Err(e) => {
                    warn!("WebSocket read error from {}: {}", peer_addr, e);
                    break;
                }
            }
        }

        send_task.abort();
        info!("Client disconnected: {}", peer_addr);
        Ok(())
    }

    /// Handles Zed Remote extension JSON-RPC requests (`git/*`, `system/*`, `terminal/*`, `fs/*`, `session/load`).
    async fn handle_extension_rpc(
        req: &JsonRpcRequest,
        session_manager: &SessionManager,
        git: &GitEngine,
        telemetry: &TelemetryCollector,
        terminal: &TerminalManager,
    ) -> Option<String> {
        match req.method.as_str() {
            "terminal/exec" => {
                let command = req.params.get("command").and_then(|v| v.as_str()).unwrap_or("");
                match terminal.exec(command).await {
                    Ok(result) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::to_value(result).unwrap_or_default(),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Terminal execution error: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "terminal/cwd" => {
                let cwd = terminal.get_cwd().await;
                Some(
                    serde_json::to_string(&JsonRpcResponse::success(
                        req.id.clone(),
                        serde_json::json!({ "cwd": cwd }),
                    ))
                    .unwrap_or_default(),
                )
            }
            "fs/list" => {
                let path_opt = req.params.get("path").and_then(|v| v.as_str());
                match terminal.list_directory(path_opt).await {
                    Ok(result) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::to_value(result).unwrap_or_default(),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Failed to list directory: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "fs/mkdir" => {
                let path_str = req.params.get("path").and_then(|v| v.as_str()).unwrap_or("");
                match terminal.create_directory(path_str).await {
                    Ok(created_path) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::json!({ "created": true, "path": created_path }),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Failed to create directory: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "workspace/set" => {
                let path_str = req.params.get("path").and_then(|v| v.as_str()).unwrap_or("");
                match terminal.set_cwd(std::path::Path::new(path_str)).await {
                    Ok(new_path) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::json!({ "workspace": new_path }),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Failed to set workspace: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "session/load" => {
                let session_id = req.params.get("sessionId").and_then(|v| v.as_str()).unwrap_or("default");
                let from_seq = req.params.get("fromSequence").and_then(|v| v.as_u64()).unwrap_or(0);
                match session_manager.replay_events(session_id, from_seq).await {
                    Ok(events) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::json!({
                                "sessionId": session_id,
                                "totalEvents": events.len(),
                                "events": events
                            }),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Failed to load session: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "git/status" => {
                match git.status().await {
                    Ok(status) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::to_value(status).unwrap_or_default(),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Git status failed: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "git/diff" => {
                let path = req.params.get("path").and_then(|v| v.as_str());
                let staged = req.params.get("staged").and_then(|v| v.as_bool()).unwrap_or(false);
                match git.diff(path, staged).await {
                    Ok(diff) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::to_value(diff).unwrap_or_default(),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Git diff failed: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "git/stage" => {
                let paths: Vec<String> = req.params.get("paths")
                    .and_then(|v| v.as_array())
                    .map(|arr| arr.iter().filter_map(|s| s.as_str().map(|str_val| str_val.to_string())).collect())
                    .unwrap_or_default();
                match git.stage(&paths).await {
                    Ok(_) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::json!({ "staged": true, "count": paths.len() }),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Git stage failed: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "git/commit" => {
                let message = req.params.get("message").and_then(|v| v.as_str()).unwrap_or("chore: update");
                let stage_all = req.params.get("stageAll").and_then(|v| v.as_bool()).unwrap_or(false);
                match git.commit(message, stage_all).await {
                    Ok(commit_result) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::to_value(commit_result).unwrap_or_default(),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Git commit failed: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "git/push" => {
                let remote = req.params.get("remote").and_then(|v| v.as_str());
                let branch = req.params.get("branch").and_then(|v| v.as_str());
                match git.push(remote, branch).await {
                    Ok(msg) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::json!({ "success": true, "message": msg }),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Git push failed: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            "system/telemetry" => {
                let report = telemetry.collect().await;
                Some(
                    serde_json::to_string(&JsonRpcResponse::success(
                        req.id.clone(),
                        serde_json::to_value(report).unwrap_or_default(),
                    ))
                    .unwrap_or_default(),
                )
            }
            "system/power" => {
                let action_str = req.params.get("action").and_then(|v| v.as_str()).unwrap_or("lock");
                let action = match action_str {
                    "sleep" => PowerAction::Sleep,
                    "shutdown" => PowerAction::Shutdown,
                    "reboot" => PowerAction::Reboot,
                    _ => PowerAction::Lock,
                };
                match telemetry.execute_power_action(action).await {
                    Ok(res) => Some(
                        serde_json::to_string(&JsonRpcResponse::success(
                            req.id.clone(),
                            serde_json::to_value(res).unwrap_or_default(),
                        ))
                        .unwrap_or_default(),
                    ),
                    Err(e) => Some(
                        serde_json::to_string(&JsonRpcResponse::error(
                            req.id.clone(),
                            error_codes::INTERNAL_ERROR,
                            format!("Power action failed: {}", e),
                        ))
                        .unwrap_or_default(),
                    ),
                }
            }
            _ => None,
        }
    }
}
