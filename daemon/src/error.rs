//! Error types for the Zed Remote daemon.

use thiserror::Error;

/// Core error enumeration covering all operational failure modes in `zed-remote-daemon`.
#[derive(Debug, Error)]
pub enum DaemonError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON serialization/deserialization error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Subprocess execution error: {0}")]
    Subprocess(String),

    #[error("WebSocket transport error: {0}")]
    WebSocket(#[from] tokio_tungstenite::tungstenite::Error),

    #[error("Authentication failed: {0}")]
    Authentication(String),

    #[error("Session error: {0}")]
    Session(String),

    #[error("Git operation error: {0}")]
    Git(String),

    #[error("Security violation: {0}")]
    Security(String),

    #[error("System telemetry error: {0}")]
    Telemetry(String),

    #[error("Invalid configuration: {0}")]
    Config(String),
}

/// Convenience alias for `Result<T, DaemonError>`.
pub type Result<T> = std::result::Result<T, DaemonError>;
