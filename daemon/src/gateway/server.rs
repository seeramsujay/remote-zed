//! Asynchronous WebSocket server managing mobile client connections, terminal, and extension RPCs.

use crate::error::Result;
use crate::gateway::auth::AuthValidator;
use crate::git::GitEngine;
use crate::protocol::{error_codes, JsonRpcMessage, JsonRpcRequest, JsonRpcResponse, RequestId};
use crate::proxy::MessageRouter;
use crate::security::SecurityGuard;
use crate::session::SessionManager;
use crate::telemetry::{PowerAction, TelemetryCollector};
use crate::terminal::TerminalManager;
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::accept_hdr_async;
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, error, info, warn};

fn percent_decode(s: &str) -> String {
    let mut bytes = Vec::new();
    let mut chars = s.bytes();
    while let Some(b) = chars.next() {
        if b == b'%' {
            let h1 = chars.next();
            let h2 = chars.next();
            if let (Some(c1), Some(c2)) = (h1, h2) {
                if let Ok(byte) = u8::from_str_radix(&format!("{}{}", c1 as char, c2 as char), 16) {
                    bytes.push(byte);
                    continue;
                }
            }
        } else if b == b'+' {
            bytes.push(b' ');
            continue;
        }
        bytes.push(b);
    }
    String::from_utf8_lossy(&bytes).into_owned()
}

/// A custom user thread representation.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CustomThread {
    pub id: String,
    pub title: String,
    pub status: String,
}

/// State of an active thread for v2 mobile clients.
#[derive(Clone, Debug)]
pub struct ThreadState {
    pub current_mode: String,
    pub messages: Vec<serde_json::Value>,
    pub transcript: Vec<serde_json::Value>,
    pub custom_threads: Vec<CustomThread>,
}

impl Default for ThreadState {
    fn default() -> Self {
        Self {
            current_mode: "yolo".to_string(),
            messages: Vec::new(),
            transcript: Vec::new(),
            custom_threads: Vec::new(),
        }
    }
}

/// Orchestrates the mobile WebSocket gateway.
pub struct WebSocketGateway {
    bind_addr: SocketAddr,
    auth: AuthValidator,
    router: MessageRouter,
    session_manager: SessionManager,
    git: GitEngine,
    telemetry: Arc<TelemetryCollector>,
    terminal: Arc<TerminalManager>,
    security: SecurityGuard,
    thread_state: Arc<tokio::sync::Mutex<ThreadState>>,
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
        security: SecurityGuard,
    ) -> Self {
        Self {
            bind_addr,
            auth,
            router,
            session_manager,
            git,
            telemetry,
            terminal,
            security,
            thread_state: Arc::new(tokio::sync::Mutex::new(ThreadState::default())),
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
                    let security = self.security.clone();
                    let thread_state = Arc::clone(&self.thread_state);

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
                            security,
                            thread_state,
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
        mut stream: TcpStream,
        peer_addr: SocketAddr,
        auth: AuthValidator,
        router: MessageRouter,
        session_manager: SessionManager,
        git: GitEngine,
        telemetry: Arc<TelemetryCollector>,
        terminal: Arc<TerminalManager>,
        security: SecurityGuard,
        thread_state: Arc<tokio::sync::Mutex<ThreadState>>,
    ) -> Result<()> {
        // Detect standard HTTP REST requests vs WebSocket upgrades
        let mut peek_buf = [0u8; 512];
        let bytes_peeked = stream.peek(&mut peek_buf).await.unwrap_or(0);
        let peek_str = std::str::from_utf8(&peek_buf[..bytes_peeked]).unwrap_or("");

        let is_websocket = peek_str.to_lowercase().contains("upgrade: websocket");
        let is_http = peek_str.starts_with("GET ")
            || peek_str.starts_with("POST ")
            || peek_str.starts_with("PUT ")
            || peek_str.starts_with("DELETE ")
            || peek_str.starts_with("OPTIONS ");
        if !is_websocket && is_http {
            return Self::handle_http_request(
                stream,
                peer_addr,
                auth,
                terminal,
                git,
                security,
                session_manager,
                router,
                thread_state,
            ).await;
        }

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
    /// Handles incoming HTTP REST and SSE requests from the mobile app.
    async fn handle_http_request(
        mut stream: TcpStream,
        peer_addr: SocketAddr,
        auth: AuthValidator,
        terminal: Arc<TerminalManager>,
        git: GitEngine,
        security: SecurityGuard,
        session_manager: SessionManager,
        router: MessageRouter,
        thread_state: Arc<tokio::sync::Mutex<ThreadState>>,
    ) -> Result<()> {
        let mut buffer = vec![0u8; 16384];
        let bytes_read = stream.read(&mut buffer).await.unwrap_or(0);
        if bytes_read == 0 {
            return Ok(());
        }
        let request_str = String::from_utf8_lossy(&buffer[..bytes_read]);
        let mut lines = request_str.lines();
        let request_line = lines.next().unwrap_or("");
        let mut parts = request_line.split_whitespace();
        let method = parts.next().unwrap_or("GET");
        let path_and_query = parts.next().unwrap_or("/");

        let (path, query) = path_and_query.split_once('?').unwrap_or((path_and_query, ""));

        let body = if let Some(pos) = request_str.find("\r\n\r\n") {
            &request_str[pos + 4..]
        } else if let Some(pos) = request_str.find("\n\n") {
            &request_str[pos + 2..]
        } else {
            ""
        };

        let mut token = "";
        for line in request_str.lines() {
            if line.to_lowercase().starts_with("authorization: bearer ") {
                token = line[22..].trim();
                break;
            }
        }
        if token.is_empty() {
            for param in query.split('&') {
                if let Some(val) = param.strip_prefix("token=") {
                    token = val;
                    break;
                }
            }
        }

        if method == "OPTIONS" {
            let resp = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Authorization, Content-Type, Accept\r\nContent-Length: 0\r\n\r\n";
            let _ = stream.write_all(resp.as_bytes()).await;
            return Ok(());
        }

        let (status_code, json_resp) = if path == "/v2/status" || path == "/status" {
            (200, serde_json::json!({
                "status": "ok",
                "api_version": 2,
                "name": "Zed-Desktop",
                "version": "2.0.0",
                "gateway": "zed-remote-daemon"
            }))
        } else if path == "/v1/status" {
            (200, serde_json::json!({
                "status": "ok",
                "api_version": 1,
                "name": "Zed-Desktop",
                "version": "2.0.0",
                "gateway": "zed-remote-daemon"
            }))
        } else if path == "/v2/pair/claim" && method == "POST" {
            (200, serde_json::json!({
                "device_id": "bunker-phone",
                "credential": auth.token()
            }))
        } else {
            if !token.is_empty() && !auth.validate(token) {
                warn!("Rejecting unauthorized HTTP request to {} from {}", path, peer_addr);
                let err_resp = "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: 26\r\n\r\n{\"error\":\"unauthorized\"}";
                let _ = stream.write_all(err_resp.as_bytes()).await;
                return Ok(());
            }

            if path == "/v2/projects/catalog" || path == "/v2/projects" {
                let cwd = terminal.get_cwd().await;
                let name = std::path::Path::new(&cwd)
                    .file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_else(|| "workspace".to_string());
                (200, serde_json::json!({
                    "projects": [{
                        "id": "current-project",
                        "name": name,
                        "path": cwd,
                        "is_open": true,
                        "kind": "local"
                    }]
                }))
            } else if path.ends_with("/threads") && method == "GET" {
                let state = thread_state.lock().await;
                let mut threads_list = vec![serde_json::json!({
                    "id": "main-thread",
                    "title": "AntiGravity AI Workspace",
                    "status": "ready"
                })];
                for ct in &state.custom_threads {
                    threads_list.push(serde_json::json!({
                        "id": ct.id,
                        "title": ct.title,
                        "status": ct.status
                    }));
                }
                (200, serde_json::json!({ "threads": threads_list }))
            } else if (path == "/v2/threads" || path.ends_with("/threads")) && method == "POST" {
                let thread_id = format!("thread-{}", chrono::Utc::now().timestamp_millis());
                let title = "New Conversation".to_string();
                let mut state = thread_state.lock().await;
                state.custom_threads.push(CustomThread {
                    id: thread_id.clone(),
                    title: title.clone(),
                    status: "ready".to_string(),
                });
                (200, serde_json::json!({
                    "id": thread_id,
                    "title": title,
                    "status": "ready"
                }))
            } else if path.ends_with("/agents") && method == "GET" {
                (200, serde_json::json!({
                    "agents": [{
                        "id": "antigravity",
                        "name": "AntiGravity Agent",
                        "is_native": false
                    }]
                }))
            } else if path.contains("/threads/") && path.ends_with("/configuration") {
                if method == "PUT" {
                    let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                    let mut state = thread_state.lock().await;
                    if let Some(mode_id) = body_json.get("mode_id").and_then(|v| v.as_str()) {
                        state.current_mode = mode_id.to_string();
                        router.set_mode(mode_id).await;
                    }
                    let mode = state.current_mode.clone();
                    drop(state);
                    (200, serde_json::json!({
                        "model": null,
                        "thinking_enabled": false,
                        "agent": {
                            "id": "antigravity",
                            "name": "AntiGravity Agent",
                            "is_native": false
                        },
                        "modes": {
                            "current": mode,
                            "available": [
                                {
                                    "id": "yolo",
                                    "name": "YOLO",
                                    "description": "Autonomous auto-pilot with auto-approved permissions (--dangerously-skip-permissions)"
                                },
                                {
                                    "id": "auto",
                                    "name": "Auto",
                                    "description": "Autonomous execution with permission confirmations"
                                },
                                {
                                    "id": "plan",
                                    "name": "Plan",
                                    "description": "Read-only planning without modifications"
                                }
                            ]
                        },
                        "options": []
                    }))
                } else {
                    let state = thread_state.lock().await;
                    let mode = state.current_mode.clone();
                    drop(state);
                    (200, serde_json::json!({
                        "model": null,
                        "thinking_enabled": false,
                        "agent": {
                            "id": "antigravity",
                            "name": "AntiGravity Agent",
                            "is_native": false
                        },
                        "modes": {
                            "current": mode,
                            "available": [
                                {
                                    "id": "yolo",
                                    "name": "YOLO",
                                    "description": "Autonomous auto-pilot with auto-approved permissions (--dangerously-skip-permissions)"
                                },
                                {
                                    "id": "auto",
                                    "name": "Auto",
                                    "description": "Autonomous execution with permission confirmations"
                                },
                                {
                                    "id": "plan",
                                    "name": "Plan",
                                    "description": "Read-only planning without modifications"
                                }
                            ]
                        },
                        "options": []
                    }))
                }
            } else if path.contains("/threads/") && path.ends_with("/changes") && method == "GET" {
                (200, serde_json::json!({
                    "files": []
                }))
            } else if path.contains("/threads/") && path.ends_with("/messages") && method == "POST" {
                let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                let text = body_json.get("text").and_then(|v| v.as_str()).unwrap_or("");
                if !text.is_empty() {
                    let mut state = thread_state.lock().await;
                    state.messages.push(serde_json::json!({
                        "role": "user",
                        "text": text
                    }));
                    state.transcript.push(serde_json::json!({
                        "kind": "user_message",
                        "body": text,
                        "timestamp": chrono::Utc::now().to_rfc3339()
                    }));
                    drop(state);

                    let prompt_rpc = serde_json::json!({
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "session/prompt",
                        "params": {
                            "sessionId": "default",
                            "prompt": [{
                                "type": "text",
                                "text": text
                            }]
                        }
                    }).to_string();
                    let _ = router.handle_mobile_message(&prompt_rpc).await;
                }
                (200, serde_json::json!({
                    "accepted": true
                }))
            } else if path.contains("/threads/") && path.ends_with("/cancel") && method == "POST" {
                let cancel_rpc = serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "session/cancel",
                    "params": {
                        "sessionId": "default"
                    }
                }).to_string();
                let _ = router.handle_mobile_message(&cancel_rpc).await;
                (200, serde_json::json!({
                    "accepted": true
                }))
            } else if path.contains("/threads/") && path.ends_with("/approvals") && method == "GET" {
                let approvals = router.get_pending_approvals().await;
                (200, serde_json::json!({
                    "approvals": approvals
                }))
            } else if path.contains("/threads/") && path.contains("/approvals/") && path.ends_with("/resolve") && method == "POST" {
                let tool_call_id = path
                    .strip_suffix("/resolve")
                    .and_then(|p| p.split("/approvals/").nth(1))
                    .unwrap_or("");
                let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                let option_id = body_json
                    .get("option_id")
                    .and_then(|v| v.as_str())
                    .or_else(|| body_json.get("decision").and_then(|v| v.as_str()))
                    .unwrap_or("allow_once");
                let resolved = router.resolve_approval(tool_call_id, option_id).await;
                if resolved {
                    (200, serde_json::json!({ "accepted": true }))
                } else {
                    (404, serde_json::json!({ "error": "Approval not found or already resolved" }))
                }
            } else if path.contains("/threads/") && path.ends_with("/elicitations") && method == "GET" {
                (200, serde_json::json!({
                    "elicitations": []
                }))
            } else if path.contains("/threads/") && path.contains("/elicitations/") && path.ends_with("/respond") && method == "POST" {
                (200, serde_json::json!({
                    "accepted": true
                }))
            } else if (path.starts_with("/v2/threads/") || path.starts_with("/threads/")) && method == "GET" {
                let thread_id = path.rsplit('/').next().unwrap_or("main-thread");
                let state = thread_state.lock().await;
                let approvals = router.get_pending_approvals().await;
                if thread_id == "main-thread" {
                    let mut messages = state.messages.clone();
                    if messages.is_empty() {
                        messages = session_manager.get_chat_messages(None).await;
                    }
                    (200, serde_json::json!({
                        "id": "main-thread",
                        "title": "AntiGravity AI Workspace",
                        "status": "ready",
                        "messages": messages,
                        "transcript": state.transcript,
                        "approvals": approvals,
                        "elicitations": []
                    }))
                } else {
                    let title = state
                        .custom_threads
                        .iter()
                        .find(|t| t.id == thread_id)
                        .map(|t| t.title.as_str())
                        .unwrap_or("New Conversation");
                    (200, serde_json::json!({
                        "id": thread_id,
                        "title": title,
                        "status": "ready",
                        "messages": [],
                        "transcript": [],
                        "approvals": approvals,
                        "elicitations": []
                    }))
                }
            } else {
                match (method, path) {
                ("POST", "/v2/terminal/exec") => {
                    let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                    let cmd = body_json.get("command").and_then(|v| v.as_str()).unwrap_or("");
                    match terminal.exec(cmd).await {
                        Ok(res) => (200, serde_json::to_value(res).unwrap_or_default()),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("GET", "/v2/fs/list") => {
                    let mut target_path = None;
                    for param in query.split('&') {
                        if let Some(val) = param.strip_prefix("path=") {
                            let decoded = percent_decode(val);
                            if !decoded.trim().is_empty() {
                                target_path = Some(decoded);
                            }
                            break;
                        }
                    }
                    match terminal.list_directory(target_path.as_deref()).await {
                        Ok(res) => (200, serde_json::to_value(res).unwrap_or_default()),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("POST", "/v2/fs/mkdir") => {
                    let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                    let path_arg = body_json.get("path").and_then(|v| v.as_str()).unwrap_or("");
                    match terminal.create_directory(path_arg).await {
                        Ok(p) => (200, serde_json::json!({ "path": p, "created": true })),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("POST", "/v2/workspace/set") => {
                    let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                    let path_arg = body_json.get("path").and_then(|v| v.as_str()).unwrap_or("");
                    match terminal.set_cwd(std::path::Path::new(path_arg)).await {
                        Ok(p) => (200, serde_json::json!({ "workspace": p, "accepted": true })),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("POST", "/v2/workspace/trust") => {
                    let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                    let path_arg = body_json.get("path").and_then(|v| v.as_str()).unwrap_or("");
                    let expanded = if path_arg.starts_with('~') {
                        if let Ok(home) = std::env::var("HOME") {
                            path_arg.replacen('~', &home, 1)
                        } else {
                            path_arg.to_string()
                        }
                    } else {
                        path_arg.to_string()
                    };
                    security.trust_path(std::path::PathBuf::from(&expanded)).await;
                    (200, serde_json::json!({ "trusted": true, "path": expanded }))
                }
                ("GET", "/v2/git/status") => {
                    match git.status().await {
                        Ok(st) => (200, serde_json::to_value(st).unwrap_or_default()),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("POST", "/v2/git/stage") => {
                    let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                    let paths: Vec<String> = body_json
                        .get("paths")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|s| s.as_str().map(String::from)).collect())
                        .unwrap_or_default();
                    match git.stage(&paths).await {
                        Ok(_) => (200, serde_json::json!({ "success": true })),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("POST", "/v2/git/unstage") => {
                    let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                    let paths: Vec<String> = body_json
                        .get("paths")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|s| s.as_str().map(String::from)).collect())
                        .unwrap_or_default();
                    match git.unstage(&paths).await {
                        Ok(_) => (200, serde_json::json!({ "success": true })),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("POST", "/v2/git/commit") => {
                    let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                    let message = body_json.get("message").and_then(|v| v.as_str()).unwrap_or("");
                    let stage_all = body_json.get("stage_all").and_then(|v| v.as_bool()).unwrap_or(false);
                    match git.commit(message, stage_all).await {
                        Ok(res) => (200, serde_json::to_value(res).unwrap_or_default()),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("POST", "/v2/git/push") => {
                    let body_json: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
                    let remote = body_json.get("remote").and_then(|v| v.as_str());
                    let branch = body_json.get("branch").and_then(|v| v.as_str());
                    match git.push(remote, branch).await {
                        Ok(out) => (200, serde_json::json!({ "output": out })),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("GET", "/v2/git/branches") => {
                    match git.branches().await {
                        Ok(branches) => (200, serde_json::json!({ "branches": branches })),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                ("GET", "/v2/git/log") | ("GET", "/v2/git/graph") => {
                    match git.log_graph(30).await {
                        Ok(commits) => (200, serde_json::json!({ "commits": commits })),
                        Err(e) => (500, serde_json::json!({ "error": e.to_string() })),
                    }
                }
                }
                ("GET", "/v2/events") => {
                    let sse_header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n";
                    if stream.write_all(sse_header.as_bytes()).await.is_ok() {
                        let mut rx = router.subscribe_mobile();
                        let initial = "data: {\"type\":\"ping\"}\n\n";
                        let _ = stream.write_all(initial.as_bytes()).await;
                        while let Ok(msg) = rx.recv().await {
                            let frame = format!("data: {}\n\n", msg);
                            if stream.write_all(frame.as_bytes()).await.is_err() {
                                break;
                            }
                        }
                    }
                    return Ok(());
                }
                _ => (404, serde_json::json!({ "error": "not found" })),
                }
            }
        };

        let body_bytes = serde_json::to_vec(&json_resp).unwrap_or_default();
        let response_header = format!(
            "HTTP/1.1 {} OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\nContent-Length: {}\r\n\r\n",
            status_code,
            body_bytes.len()
        );
        let _ = stream.write_all(response_header.as_bytes()).await;
        let _ = stream.write_all(&body_bytes).await;
        Ok(())
    }

}
