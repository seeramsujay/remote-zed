//! Append-only session event logger persisting transactions to `.jsonl` files.

use crate::error::Result;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tokio::fs::{create_dir_all, OpenOptions};
use tokio::io::AsyncWriteExt;
use tokio::sync::Mutex;
use tracing::{debug, error};

/// Direction of an observed protocol message.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MessageDirection {
    ZedToAgent,
    AgentToZed,
    MobileToAgent,
    DaemonToMobile,
}

/// A single recorded transaction frame written to the `.jsonl` session log.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionLogEntry {
    pub seq: u64,
    pub timestamp: String,
    pub direction: MessageDirection,
    pub frame: serde_json::Value,
}

/// Manages writing atomic log entries to an append-only file for a specific session.
pub struct SessionLogger {
    session_id: String,
    file_path: PathBuf,
    sequence: Mutex<u64>,
}

impl SessionLogger {
    /// Initializes or opens a session logger for a specific session directory and session ID.
    pub async fn new(base_dir: &Path, session_id: &str) -> Result<Self> {
        create_dir_all(base_dir).await?;
        let file_path = base_dir.join(format!("{}.jsonl", session_id));

        // Calculate initial sequence number by inspecting the tail if file exists
        let mut initial_seq = 0;
        if file_path.exists() {
            if let Ok(metadata) = tokio::fs::metadata(&file_path).await {
                let file_len = metadata.len();
                if file_len > 0 {
                    let seek_pos = file_len.saturating_sub(8192);
                    if let Ok(mut file) = tokio::fs::File::open(&file_path).await {
                        use tokio::io::{AsyncBufReadExt, AsyncSeekExt};
                        let _ = file.seek(std::io::SeekFrom::Start(seek_pos)).await;
                        let mut reader = tokio::io::BufReader::new(file).lines();
                        if seek_pos > 0 {
                            let _ = reader.next_line().await; // discard partial line
                        }
                        while let Ok(Some(line)) = reader.next_line().await {
                            let trimmed = line.trim();
                            if !trimmed.is_empty() {
                                if let Ok(entry) = serde_json::from_str::<serde_json::Value>(trimmed) {
                                    if let Some(s) = entry.get("seq").and_then(|v| v.as_u64()) {
                                        initial_seq = s;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(Self {
            session_id: session_id.to_string(),
            file_path,
            sequence: Mutex::new(initial_seq),
        })
    }

    /// Appends a message frame to the session log file.
    pub async fn log(&self, direction: MessageDirection, frame: &serde_json::Value) {
        let mut seq_lock = self.sequence.lock().await;
        *seq_lock += 1;
        let seq = *seq_lock;

        let entry = SessionLogEntry {
            seq,
            timestamp: Utc::now().to_rfc3339(),
            direction,
            frame: frame.clone(),
        };

        match serde_json::to_string(&entry) {
            Ok(line) => {
                match OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(&self.file_path)
                    .await
                {
                    Ok(mut file) => {
                        let record = format!("{}\n", line);
                        if let Err(e) = file.write_all(record.as_bytes()).await {
                            error!("Failed to write to session log {:?}: {}", self.file_path, e);
                        }
                    }
                    Err(e) => {
                        error!("Failed to open session log {:?}: {}", self.file_path, e);
                    }
                }
            }
            Err(e) => {
                error!("Failed to serialize session log entry for session {}: {}", self.session_id, e);
            }
        }

        debug!("Logged frame #{} for session {}", seq, self.session_id);
    }

    /// Reads all entries from the `.jsonl` log file starting from a given sequence number.
    pub async fn read_events_from(&self, from_seq: u64) -> Result<Vec<SessionLogEntry>> {
        if !self.file_path.exists() {
            return Ok(Vec::new());
        }

        let content = tokio::fs::read_to_string(&self.file_path).await?;
        let mut entries = Vec::new();

        for line in content.lines() {
            if line.trim().is_empty() {
                continue;
            }
            if let Ok(entry) = serde_json::from_str::<SessionLogEntry>(line) {
                if entry.seq >= from_seq {
                    entries.push(entry);
                }
            }
        }

        Ok(entries)
    }
}
