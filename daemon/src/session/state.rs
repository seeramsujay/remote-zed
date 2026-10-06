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
}
