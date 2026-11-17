//! Session state coordination, single-writer mutex locks, and event replay.

use crate::error::Result;
use crate::session::logger::{MessageDirection, SessionLogEntry, SessionLogger};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::AsyncBufReadExt;
use tokio::sync::{Mutex, RwLock};
use tracing::{info, warn};

/// Parsed in-memory cache of session transactions.
#[derive(Clone, Default)]
pub struct SessionCache {
    pub file_len: u64,
    pub messages: Vec<serde_json::Value>,
    pub transcript: Vec<serde_json::Value>,
}

/// Tracks the active execution state of a specific session.
pub struct SessionEntry {
    pub session_id: String,
    pub logger: Arc<SessionLogger>,
    /// Mutex held while a prompt turn is in flight. Tracks the instant the lock was acquired.
    pub busy_since: Mutex<Option<std::time::Instant>>,
    /// In-memory cache for fast, zero-copy thread polling.
    pub cache: Mutex<Option<SessionCache>>,
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
            busy_since: Mutex::new(None),
            cache: Mutex::new(None),
        });

        write_guard.insert(session_id.to_string(), Arc::clone(&entry));
        info!("Registered new session tracker for {}", session_id);
        Ok(entry)
    }

    /// Marks the session as executing an active prompt turn.
    /// Never rejects prompts so mobile messages are always accepted and processed.
    pub async fn acquire_prompt_lock(&self, session_id: &str) -> Result<()> {
        let entry = self.get_or_create(session_id).await?;
        let mut busy = entry.busy_since.lock().await;
        *busy = Some(std::time::Instant::now());
        Ok(())
    }

    /// Keeps the prompt lease fresh while agent is emitting progress/chunks.
    pub async fn touch_prompt_lock(&self, session_id: &str) {
        if let Ok(entry) = self.get_or_create(session_id).await {
            let mut busy = entry.busy_since.lock().await;
            if busy.is_some() {
                *busy = Some(std::time::Instant::now());
            }
        }
    }

    /// Releases the prompt lease for a session upon turn completion or failure.
    pub async fn release_prompt_lock(&self, session_id: &str) {
        if let Ok(entry) = self.get_or_create(session_id).await {
            let mut busy = entry.busy_since.lock().await;
            *busy = None;
        }
    }

    /// Checks if a session is currently running an active prompt turn.
    pub async fn is_session_busy(&self, session_id: &str) -> bool {
        if let Ok(entry) = self.get_or_create(session_id).await {
            let busy = entry.busy_since.lock().await;
            if let Some(since) = *busy {
                if since.elapsed() <= std::time::Duration::from_secs(45) {
                    return true;
                }
            }
        }
        false
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

    /// Resolves the session ID and file path for a requested or latest session.
    pub async fn resolve_session_file(&self, preferred_session_id: Option<&str>) -> Option<(String, PathBuf)> {
        if let Some(id) = preferred_session_id {
            let p = self.base_dir.join(format!("{}.jsonl", id));
            if p.exists() {
                return Some((id.to_string(), p));
            }
        }
        let mut latest_file: Option<(String, PathBuf, std::time::SystemTime)> = None;
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
                        if latest_file.as_ref().map_or(true, |(_, _, m)| modified > *m) {
                            latest_file = Some((stem, path, modified));
                        }
                    }
                }
            }
        }
        latest_file.map(|(id, path, _)| (id, path))
    }

    /// Parses a session `.jsonl` file in a single streaming pass into chat messages and rich transcript.
    pub async fn parse_session_file(path: &std::path::Path) -> std::io::Result<(Vec<serde_json::Value>, Vec<serde_json::Value>)> {
        let file = tokio::fs::File::open(path).await?;

        let mut messages = Vec::new();
        let mut transcript = Vec::new();
        let mut current_thought_chunks: Vec<String> = Vec::new();
        let mut current_assistant_chunks: Vec<String> = Vec::new();

        let flush_thought = |transcript: &mut Vec<serde_json::Value>, chunks: &mut Vec<String>| {
            if !chunks.is_empty() {
                let text = chunks.join("");
                let clean = text.trim();
                if !clean.is_empty() {
                    let idx = transcript.len();
                    transcript.push(serde_json::json!({
                        "index": idx,
                        "kind": "thought",
                        "text": clean,
                        "chunks": [{ "kind": "thought", "text": clean }],
                        "details_available": false
                    }));
                }
                chunks.clear();
            }
        };

        let flush_assistant = |transcript: &mut Vec<serde_json::Value>, messages: &mut Vec<serde_json::Value>, chunks: &mut Vec<String>| {
            if !chunks.is_empty() {
                let text = chunks.join("");
                let clean = text.trim();
                if !clean.is_empty() {
                    let idx = transcript.len();
                    transcript.push(serde_json::json!({
                        "index": idx,
                        "kind": "assistant_message",
                        "text": clean,
                        "chunks": [{ "kind": "text", "text": clean }],
                        "details_available": false
                    }));
                    messages.push(serde_json::json!({
                        "role": "assistant",
                        "text": clean
                    }));
                }
                chunks.clear();
            }
        };

        let mut reader = tokio::io::BufReader::new(file).lines();
        while let Ok(Some(line)) = reader.next_line().await {
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
                flush_thought(&mut transcript, &mut current_thought_chunks);
                flush_assistant(&mut transcript, &mut messages, &mut current_assistant_chunks);

                let p = frame.get("params").and_then(|p| p.get("prompt"));
                let user_text = if let Some(arr) = p.and_then(|p| p.as_array()) {
                    let mut parts = Vec::new();
                    for item in arr {
                        if let Some(t) = item.get("text").and_then(|t| t.as_str()) {
                            let clean = t.trim();
                            if !clean.is_empty() {
                                parts.push(clean);
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
                    let idx = transcript.len();
                    transcript.push(serde_json::json!({
                        "index": idx,
                        "kind": "user_message",
                        "text": clean_user,
                        "chunks": [{ "kind": "text", "text": clean_user }],
                        "details_available": false
                    }));
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

                if t == "agent_thought_chunk" {
                    flush_assistant(&mut transcript, &mut messages, &mut current_assistant_chunks);
                    if let Some(chunk_text) = update
                        .get("content")
                        .and_then(|c| c.get("text"))
                        .and_then(|t| t.as_str())
                    {
                        current_thought_chunks.push(chunk_text.to_string());
                    }
                } else if t == "agent_message_chunk" {
                    flush_thought(&mut transcript, &mut current_thought_chunks);
                    if let Some(chunk_text) = update
                        .get("content")
                        .and_then(|c| c.get("text"))
                        .and_then(|t| t.as_str())
                    {
                        current_assistant_chunks.push(chunk_text.to_string());
                    }
                } else if t == "tool_call" {
                    flush_thought(&mut transcript, &mut current_thought_chunks);
                    flush_assistant(&mut transcript, &mut messages, &mut current_assistant_chunks);

                    let tool_call_id = update
                        .get("toolCallId")
                        .or_else(|| update.get("tool_call_id"))
                        .and_then(|id| id.as_str())
                        .unwrap_or("")
                        .to_string();
                    let tool_name = update
                        .get("name")
                        .or_else(|| update.get("tool_name"))
                        .and_then(|n| n.as_str())
                        .unwrap_or("tool")
                        .to_string();
                    let title = update
                        .get("title")
                        .and_then(|t| t.as_str())
                        .unwrap_or(&tool_name)
                        .to_string();
                    let status = update
                        .get("status")
                        .and_then(|s| s.as_str())
                        .unwrap_or("in_progress")
                        .to_string();
                    let raw_input = update
                        .get("rawInput")
                        .or_else(|| update.get("raw_input"))
                        .or_else(|| update.get("args"))
                        .or_else(|| update.get("parameters"))
                        .cloned()
                        .unwrap_or(serde_json::Value::Null);

                    let idx = transcript.len();
                    transcript.push(serde_json::json!({
                        "index": idx,
                        "kind": "tool",
                        "tool_call_id": tool_call_id,
                        "tool_name": tool_name,
                        "title": title,
                        "status": status,
                        "raw_input": raw_input,
                        "details_available": true
                    }));
                } else if t == "tool_call_update" {
                    let tool_call_id = update
                        .get("toolCallId")
                        .or_else(|| update.get("tool_call_id"))
                        .and_then(|id| id.as_str())
                        .unwrap_or("");
                    let status = update
                        .get("status")
                        .and_then(|s| s.as_str())
                        .unwrap_or("completed");
                    let raw_output = update
                        .get("rawOutput")
                        .or_else(|| update.get("raw_output"))
                        .or_else(|| update.get("content"))
                        .cloned()
                        .unwrap_or(serde_json::Value::Null);

                    let mut found = false;
                    for entry in transcript.iter_mut().rev() {
                        if entry.get("tool_call_id").and_then(|id| id.as_str()) == Some(tool_call_id) {
                            if let Some(obj) = entry.as_object_mut() {
                                obj.insert("status".to_string(), serde_json::Value::String(status.to_string()));
                                obj.insert("raw_output".to_string(), raw_output.clone());
                            }
                            found = true;
                            break;
                        }
                    }
                    if !found && !tool_call_id.is_empty() {
                        let idx = transcript.len();
                        transcript.push(serde_json::json!({
                            "index": idx,
                            "kind": "tool",
                            "tool_call_id": tool_call_id,
                            "status": status,
                            "raw_output": raw_output,
                            "details_available": true
                        }));
                    }
                }
            }
        }

        flush_thought(&mut transcript, &mut current_thought_chunks);
        flush_assistant(&mut transcript, &mut messages, &mut current_assistant_chunks);

        Ok((messages, transcript))
    }

    /// Retrieves parsed messages and transcript with fast in-memory caching.
    pub async fn get_session_data(&self, preferred_session_id: Option<&str>) -> (Vec<serde_json::Value>, Vec<serde_json::Value>) {
        let (target_id, file_path) = match self.resolve_session_file(preferred_session_id).await {
            Some(pair) => pair,
            None => return (Vec::new(), Vec::new()),
        };

        let entry = match self.get_or_create(&target_id).await {
            Ok(e) => e,
            Err(_) => return (Vec::new(), Vec::new()),
        };

        let current_len = match tokio::fs::metadata(&file_path).await {
            Ok(m) => m.len(),
            Err(_) => return (Vec::new(), Vec::new()),
        };

        let mut cache_guard = entry.cache.lock().await;
        if let Some(ref cache) = *cache_guard {
            if cache.file_len == current_len {
                return (cache.messages.clone(), cache.transcript.clone());
            }
        }

        match Self::parse_session_file(&file_path).await {
            Ok((messages, transcript)) => {
                *cache_guard = Some(SessionCache {
                    file_len: current_len,
                    messages: messages.clone(),
                    transcript: transcript.clone(),
                });
                (messages, transcript)
            }
            Err(e) => {
                warn!("Failed to parse session file {:?}: {}", file_path, e);
                if let Some(ref cache) = *cache_guard {
                    (cache.messages.clone(), cache.transcript.clone())
                } else {
                    (Vec::new(), Vec::new())
                }
            }
        }
    }

    /// Extracts structured chat messages ({ "role": "user" | "assistant", "text": "..." }) from the latest or specified session log.
    pub async fn get_chat_messages(&self, preferred_session_id: Option<&str>) -> Vec<serde_json::Value> {
        self.get_session_data(preferred_session_id).await.0
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
        self.get_session_data(preferred_session_id).await.1
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

                    // Scan first 60 lines to extract title and check if it has messages
                    let mut title: Option<String> = None;
                    let mut first_prompt: Option<String> = None;
                    let mut has_turns = false;

                    if let Ok(file) = tokio::fs::File::open(&path).await {
                        let mut reader = tokio::io::BufReader::new(file).lines();
                        let mut line_count = 0;
                        while let Ok(Some(line)) = reader.next_line().await {
                            line_count += 1;
                            if line_count > 60 {
                                break;
                            }
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
                            if title.is_some() && has_turns {
                                break;
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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_prompt_lock_lifecycle() {
        let temp_dir = std::env::temp_dir().join(format!("zed-test-{}", uuid::Uuid::new_v4()));
        let manager = SessionManager::new(temp_dir.clone());

        let sid = "session-test-lock";
        assert!(!manager.is_session_busy(sid).await);

        manager.acquire_prompt_lock(sid).await.expect("Should acquire lock");
        assert!(manager.is_session_busy(sid).await);

        manager.touch_prompt_lock(sid).await;
        assert!(manager.is_session_busy(sid).await);

        manager.release_prompt_lock(sid).await;
        assert!(!manager.is_session_busy(sid).await);

        let _ = tokio::fs::remove_dir_all(temp_dir).await;
    }

    #[tokio::test]
    async fn test_rich_chat_transcript_parsing() {
        let temp_dir = std::env::temp_dir().join(format!("zed-test-{}", uuid::Uuid::new_v4()));
        tokio::fs::create_dir_all(&temp_dir).await.unwrap();
        let manager = SessionManager::new(temp_dir.clone());

        let sid = "session-transcript-test";
        let log_path = temp_dir.join(format!("{}.jsonl", sid));

        let entries = [
            serde_json::json!({
                "seq": 1,
                "timestamp": "2026-11-16T10:00:00Z",
                "direction": "mobile_to_agent",
                "frame": {
                    "method": "session/prompt",
                    "params": {
                        "prompt": [{ "type": "text", "text": "Fix the phone sync issue" }]
                    }
                }
            }),
            serde_json::json!({
                "seq": 2,
                "timestamp": "2026-11-16T10:00:01Z",
                "direction": "agent_to_zed",
                "frame": {
                    "method": "session/update",
                    "params": {
                        "update": {
                            "sessionUpdate": "agent_thought_chunk",
                            "content": { "text": "Analyzing the logs... " }
                        }
                    }
                }
            }),
            serde_json::json!({
                "seq": 3,
                "timestamp": "2026-11-16T10:00:02Z",
                "direction": "agent_to_zed",
                "frame": {
                    "method": "session/update",
                    "params": {
                        "update": {
                            "sessionUpdate": "agent_thought_chunk",
                            "content": { "text": "Found prompt lock bug." }
                        }
                    }
                }
            }),
            serde_json::json!({
                "seq": 4,
                "timestamp": "2026-11-16T10:00:03Z",
                "direction": "agent_to_zed",
                "frame": {
                    "method": "session/update",
                    "params": {
                        "update": {
                            "sessionUpdate": "tool_call",
                            "toolCallId": "call_123",
                            "name": "run_command",
                            "title": "Check git status",
                            "status": "in_progress",
                            "rawInput": { "command": "git status" }
                        }
                    }
                }
            }),
            serde_json::json!({
                "seq": 5,
                "timestamp": "2026-11-16T10:00:04Z",
                "direction": "agent_to_zed",
                "frame": {
                    "method": "session/update",
                    "params": {
                        "update": {
                            "sessionUpdate": "tool_call_update",
                            "toolCallId": "call_123",
                            "status": "completed",
                            "rawOutput": { "exit_code": 0, "stdout": "clean" }
                        }
                    }
                }
            }),
            serde_json::json!({
                "seq": 6,
                "timestamp": "2026-11-16T10:00:05Z",
                "direction": "agent_to_zed",
                "frame": {
                    "method": "session/update",
                    "params": {
                        "update": {
                            "sessionUpdate": "agent_message_chunk",
                            "content": { "text": "Issue is resolved!" }
                        }
                    }
                }
            }),
        ];

        let mut content = String::new();
        for e in &entries {
            content.push_str(&e.to_string());
            content.push('\n');
        }
        tokio::fs::write(&log_path, content).await.unwrap();

        let transcript = manager.get_chat_transcript(Some(sid)).await;
        assert_eq!(transcript.len(), 4);

        // 1. User message
        assert_eq!(transcript[0]["kind"], "user_message");
        assert_eq!(transcript[0]["text"], "Fix the phone sync issue");

        // 2. Coalesced Thought block
        assert_eq!(transcript[1]["kind"], "thought");
        assert_eq!(transcript[1]["text"], "Analyzing the logs... Found prompt lock bug.");

        // 3. Tool call with updated status
        assert_eq!(transcript[2]["kind"], "tool");
        assert_eq!(transcript[2]["tool_call_id"], "call_123");
        assert_eq!(transcript[2]["status"], "completed");

        // 4. Assistant message
        assert_eq!(transcript[3]["kind"], "assistant_message");
        assert_eq!(transcript[3]["text"], "Issue is resolved!");

        // Also test get_chat_messages
        let msgs = manager.get_chat_messages(Some(sid)).await;
        assert_eq!(msgs.len(), 2);
        assert_eq!(msgs[0]["role"], "user");
        assert_eq!(msgs[0]["text"], "Fix the phone sync issue");
        assert_eq!(msgs[1]["role"], "assistant");
        assert_eq!(msgs[1]["text"], "Issue is resolved!");

        let _ = tokio::fs::remove_dir_all(temp_dir).await;
    }
}
