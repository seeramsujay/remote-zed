//! Session state coordination, single-writer mutex locks, and event replay.

use crate::error::{DaemonError, Result};
use crate::session::logger::{MessageDirection, SessionLogEntry, SessionLogger};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::{Mutex, RwLock};
use tracing::{info, warn};

/// Tracks the active execution state of a specific session.
pub struct SessionEntry {
    pub session_id: String,
    pub logger: Arc<SessionLogger>,
    /// Mutex held while a prompt turn is in flight. Prevents concurrent conflicting prompts.
    pub is_busy: Mutex<bool>,
}

/// Global session repository managing all active conversation threads.
#[derive(Clone)]
pub struct SessionManager {
    base_dir: PathBuf,
    sessions: Arc<RwLock<HashMap<String, Arc<SessionEntry>>>>,
}

impl SessionManager {
    /// Creates a new `SessionManager` storing logs in `base_dir`.
    pub fn new(base_dir: PathBuf) -> Self {
        Self {
            base_dir,
            sessions: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Retrieves an existing session entry or initializes a new logger for it.
    pub async fn get_or_create(&self, session_id: &str) -> Result<Arc<SessionEntry>> {
        let read_guard = self.sessions.read().await;
        if let Some(entry) = read_guard.get(session_id) {
            return Ok(Arc::clone(entry));
        }
        drop(read_guard);

        let mut write_guard = self.sessions.write().await;
        if let Some(entry) = write_guard.get(session_id) {
            return Ok(Arc::clone(entry));
        }

        let logger = SessionLogger::new(&self.base_dir, session_id).await?;
        let entry = Arc::new(SessionEntry {
            session_id: session_id.to_string(),
            logger: Arc::new(logger),
            is_busy: Mutex::new(false),
        });

        write_guard.insert(session_id.to_string(), Arc::clone(&entry));
        info!("Registered new session tracker for {}", session_id);
        Ok(entry)
    }

    /// Attempts to acquire an execution lease for a prompt turn.
    /// Returns an error if the session is currently busy processing another turn.
    pub async fn acquire_prompt_lock(&self, session_id: &str) -> Result<()> {
        let entry = self.get_or_create(session_id).await?;
        let mut busy = entry.is_busy.lock().await;
        if *busy {
            return Err(DaemonError::Session(format!(
                "Session {} is currently busy processing another turn",
                session_id
            )));
        }
        *busy = true;
        Ok(())
    }

    /// Releases the prompt lease for a session upon turn completion or failure.
    pub async fn release_prompt_lock(&self, session_id: &str) {
        if let Ok(entry) = self.get_or_create(session_id).await {
            let mut busy = entry.is_busy.lock().await;
            *busy = false;
        }
    }

    /// Logs an event frame across the appropriate session logger.
    pub async fn log_event(&self, session_id: &str, direction: MessageDirection, frame: &serde_json::Value) {
        match self.get_or_create(session_id).await {
            Ok(entry) => {
                entry.logger.log(direction, frame).await;
            }
            Err(e) => {
                warn!("Failed to log event for session {}: {}", session_id, e);
            }
        }
    }

    /// Replays events for a session starting from a specific sequence number.
    pub async fn replay_events(&self, session_id: &str, from_seq: u64) -> Result<Vec<SessionLogEntry>> {
        let entry = self.get_or_create(session_id).await?;
        entry.logger.read_events_from(from_seq).await
    }

    /// Extracts structured chat messages ({ "role": "user" | "assistant", "text": "..." }) from the latest or specified session log.
    pub async fn get_chat_messages(&self, preferred_session_id: Option<&str>) -> Vec<serde_json::Value> {
        let file_to_read = if let Some(id) = preferred_session_id {
            let p = self.base_dir.join(format!("{}.jsonl", id));
            if p.exists() {
                Some(p)
            } else {
                return Vec::new();
            }
        } else {
            let mut latest_file: Option<(PathBuf, std::time::SystemTime)> = None;
            if let Ok(mut dir_entries) = tokio::fs::read_dir(&self.base_dir).await {
                while let Ok(Some(entry)) = dir_entries.next_entry().await {
                    let path = entry.path();
                    if path.extension().and_then(|e| e.to_str()) == Some("jsonl") {
                        if let Ok(metadata) = entry.metadata().await {
                            let modified = metadata.modified().unwrap_or(std::time::SystemTime::UNIX_EPOCH);
                            if latest_file.as_ref().map_or(true, |(_, m)| modified > *m) {
                                latest_file = Some((path, modified));
                            }
                        }
                    }
                }
            }
            latest_file.map(|(p, _)| p)
        };

        let path = match file_to_read {
            Some(p) => p,
            None => return Vec::new(),
        };

        let content = match tokio::fs::read_to_string(&path).await {
            Ok(c) => c,
            Err(_) => return Vec::new(),
        };

        let mut messages = Vec::new();
        let mut current_assistant_chunks = Vec::new();

        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let data: serde_json::Value = match serde_json::from_str(trimmed) {
                Ok(v) => v,
                Err(_) => continue,
            };

            let frame = match data.get("frame") {
                Some(f) => f,
                None => continue,
            };

            let method = frame.get("method").and_then(|m| m.as_str()).unwrap_or("");
            if method == "session/prompt" {
                if !current_assistant_chunks.is_empty() {
                    let text = current_assistant_chunks.join("");
                    let clean = text.trim();
                    if !clean.is_empty() {
                        messages.push(serde_json::json!({
                            "role": "assistant",
                            "text": clean
                        }));
                    }
                    current_assistant_chunks.clear();
                }

                let p = frame.get("params").and_then(|p| p.get("prompt"));
                let user_text = if let Some(arr) = p.and_then(|p| p.as_array()) {
                    let mut parts = Vec::new();
                    for item in arr {
                        if let Some(t) = item.get("text").and_then(|t| t.as_str()) {
                            let trimmed = t.trim();
                            if !trimmed.is_empty() {
                                parts.push(trimmed);
                            }
                        }
                    }
                    parts.join("\n")
                } else if let Some(s) = p.and_then(|p| p.as_str()) {
                    s.to_string()
                } else {
                    String::new()
                };

                let clean_user = user_text.trim();
                if !clean_user.is_empty() {
                    messages.push(serde_json::json!({
                        "role": "user",
                        "text": clean_user
                    }));
                }
            } else if method == "session/update" {
                let update = match frame.get("params").and_then(|p| p.get("update")) {
                    Some(u) => u,
                    None => continue,
                };
                let t = update
                    .get("sessionUpdate")
                    .or_else(|| update.get("sessionUpdateType"))
                    .and_then(|s| s.as_str())
                    .unwrap_or("");
                if t == "agent_message_chunk" {
                    if let Some(chunk_text) = update
                        .get("content")
                        .and_then(|c| c.get("text"))
                        .and_then(|t| t.as_str())
                    {
                        current_assistant_chunks.push(chunk_text.to_string());
                    }
                }
            }
        }

        if !current_assistant_chunks.is_empty() {
            let text = current_assistant_chunks.join("");
            let clean = text.trim();
            if !clean.is_empty() {
                messages.push(serde_json::json!({
                    "role": "assistant",
                    "text": clean
                }));
            }
        }

        messages
    }

    /// Returns the session ID of the most recently updated session log.
    pub async fn get_latest_session_id(&self) -> Option<String> {
        let mut latest: Option<(String, std::time::SystemTime)> = None;
        if let Ok(mut dir_entries) = tokio::fs::read_dir(&self.base_dir).await {
            while let Ok(Some(entry)) = dir_entries.next_entry().await {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("jsonl") {
                    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string();
                    if stem.is_empty() || stem == "default" {
                        continue;
                    }
                    if let Ok(metadata) = entry.metadata().await {
                        let modified = metadata.modified().unwrap_or(std::time::SystemTime::UNIX_EPOCH);
                        if latest.as_ref().map_or(true, |(_, m)| modified > *m) {
                            latest = Some((stem, modified));
                        }
                    }
                }
            }
        }
        latest.map(|(id, _)| id)
    }

    /// Extracts structured transcript entries from the session log suitable for mobile rich transcript rendering.
    pub async fn get_chat_transcript(&self, preferred_session_id: Option<&str>) -> Vec<serde_json::Value> {
        let msgs = self.get_chat_messages(preferred_session_id).await;
        let mut transcript = Vec::with_capacity(msgs.len());
        for (idx, msg) in msgs.into_iter().enumerate() {
            let role = msg.get("role").and_then(|r| r.as_str()).unwrap_or("user");
            let text = msg.get("text").and_then(|t| t.as_str()).unwrap_or("");
            let kind = if role == "user" { "user_message" } else { "assistant_message" };
            transcript.push(serde_json::json!({
                "index": idx,
                "kind": kind,
                "text": text,
                "chunks": [
                    { "kind": "text", "text": text }
                ],
                "details_available": false
            }));
        }
        transcript
    }

    /// Discovers and lists all recorded AntiGravity/ACP conversation threads from `.jsonl` session files.
    pub async fn list_sessions(&self) -> Vec<serde_json::Value> {
        let mut sessions_info = Vec::new();
        if let Ok(mut dir_entries) = tokio::fs::read_dir(&self.base_dir).await {
            while let Ok(Some(entry)) = dir_entries.next_entry().await {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("jsonl") {
                    let session_id = path.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string();
                    if session_id.is_empty() {
                        continue;
                    }

                    let metadata = entry.metadata().await.ok();
                    let file_size = metadata.as_ref().map(|m| m.len()).unwrap_or(0);
                    if session_id == "default" && file_size == 0 {
                        continue;
                    }

                    let modified_time = metadata
                        .and_then(|m| m.modified().ok())
                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|d| d.as_secs())
                        .unwrap_or(0);

                    // Scan file to extract title and check if it has messages
                    let mut title: Option<String> = None;
                    let mut first_prompt: Option<String> = None;
                    let mut has_turns = false;

                    if let Ok(content) = tokio::fs::read_to_string(&path).await {
                        for line in content.lines() {
                            let trimmed = line.trim();
                            if trimmed.is_empty() {
                                continue;
                            }
                            if let Ok(data) = serde_json::from_str::<serde_json::Value>(trimmed) {
                                if let Some(frame) = data.get("frame") {
                                    let method = frame.get("method").and_then(|m| m.as_str()).unwrap_or("");
                                    if method == "session/prompt" {
                                        has_turns = true;
                                        if first_prompt.is_none() {
                                            if let Some(arr) = frame.get("params").and_then(|p| p.get("prompt")).and_then(|p| p.as_array()) {
                                                for item in arr {
                                                    if let Some(t) = item.get("text").and_then(|t| t.as_str()) {
                                                        let clean = t.trim();
                                                        if !clean.is_empty() {
                                                            first_prompt = Some(clean.to_string());
                                                            break;
                                                        }
                                                    }
                                                }
                                            } else if let Some(s) = frame.get("params").and_then(|p| p.get("prompt")).and_then(|p| p.as_str()) {
                                                first_prompt = Some(s.trim().to_string());
                                            }
                                        }
                                    } else if method == "session/update" {
                                        if let Some(update) = frame.get("params").and_then(|p| p.get("update")) {
                                            let update_type = update
                                                .get("sessionUpdate")
                                                .or_else(|| update.get("sessionUpdateType"))
                                                .and_then(|s| s.as_str())
                                                .unwrap_or("");
                                            if update_type == "session_info_update" {
                                                if let Some(t) = update.get("title").and_then(|t| t.as_str()) {
                                                    let clean = t.trim();
                                                    if !clean.is_empty() {
                                                        title = Some(clean.to_string());
                                                    }
                                                }
                                            } else if update_type == "agent_message_chunk" || update_type == "user_message_chunk" {
                                                has_turns = true;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Ignore sessions that have 0 messages or turns, unless it is default
                    if !has_turns && session_id != "default" && file_size < 100 {
                        continue;
                    }

                    let resolved_title = title.or_else(|| {
                        first_prompt.map(|p| {
                            if p.chars().count() > 40 {
                                format!("{}…", p.chars().take(40).collect::<String>())
                            } else {
                                p
                            }
                        })
                    }).unwrap_or_else(|| {
                        if session_id.len() >= 8 {
                            format!("AntiGravity Chat {}", &session_id[..8])
                        } else {
                            "AntiGravity Conversation".to_string()
                        }
                    });

                    sessions_info.push((
                        modified_time,
                        serde_json::json!({
                            "id": session_id,
                            "title": resolved_title,
                            "status": "ready",
                            "agent": {
                                "id": "antigravity",
                                "name": "AntiGravity Agent",
                                "is_native": false
                            },
                            "last_updated": modified_time
                        })
                    ));
                }
            }
        }

        // Sort descending by modified time (most recent first)
        sessions_info.sort_by(|a, b| b.0.cmp(&a.0));
        sessions_info.into_iter().map(|(_, val)| val).collect()
    }
}
