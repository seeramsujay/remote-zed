//! Configuration management for the Zed Remote daemon.
//!
//! Parses command-line arguments, environment variables, and authentication credentials.

use clap::Parser;
use std::path::PathBuf;
use tracing::info;

/// Command line options and runtime settings for `zed-remote-daemon`.
#[derive(Parser, Debug, Clone)]
#[command(
    name = "zed-remote-daemon",
    author = "Zed Remote Contributors",
    version,
    about = "Proxy binary intercepting Zed ACP streams and serving remote mobile clients over Tailscale."
)]
pub struct Config {
    /// Command to spawn the target AI agent process (e.g. `antigravity`, `claude-code`).
    #[arg(
        long = "target-command",
        env = "ZED_REMOTE_TARGET_COMMAND",
        default_value = "antigravity"
    )]
    pub target_command: String,

    /// Arguments to pass to the target AI agent executable.
    #[arg(
        long = "target-args",
        env = "ZED_REMOTE_TARGET_ARGS",
        default_value = "acp"
    )]
    pub target_args: String,

    /// IP address interface to bind the WebSocket server (e.g. Tailscale overlay IP `100.x.y.z` or `127.0.0.1`).
    #[arg(
        long = "bind-host",
        env = "ZED_REMOTE_BIND_HOST",
        default_value = "127.0.0.1"
    )]
    pub bind_host: String,

    /// Port to listen on for WebSocket connections from the mobile app.
    #[arg(
        long = "port",
        env = "ZED_REMOTE_PORT",
        default_value = "8443"
    )]
    pub port: u16,

    /// Optional path to a file containing the pre-shared secret bearer token.
    #[arg(
        long = "token-file",
        env = "ZED_REMOTE_TOKEN_FILE"
    )]
    pub token_file: Option<PathBuf>,

    /// Secret authentication bearer token provided directly via CLI or environment variable.
    #[arg(
        long = "auth-token",
        env = "ZED_REMOTE_AUTH_TOKEN"
    )]
    pub auth_token: Option<String>,

    /// Directory used to persist rolling `.jsonl` session transaction logs.
    #[arg(
        long = "session-dir",
        env = "ZED_REMOTE_SESSION_DIR"
    )]
    pub session_dir: Option<PathBuf>,

    /// Root directory of the repository or active project workspace.
    #[arg(
        long = "workspace-root",
        env = "ZED_REMOTE_WORKSPACE_ROOT"
    )]
    pub workspace_root: Option<PathBuf>,

    /// Blocklist of prohibited shell command substrings.
    #[arg(
        long = "blocked-commands",
        env = "ZED_REMOTE_BLOCKED_COMMANDS",
        value_delimiter = ','
    )]
    pub blocked_commands: Vec<String>,
}

impl Config {
    /// Resolves the effective authentication token from `--auth-token`, `--token-file`,
    /// or generates an ephemeral token if none was supplied.
    pub fn resolve_token(&self) -> String {
        if let Some(token) = &self.auth_token {
            if !token.trim().is_empty() {
                return token.trim().to_string();
            }
        }

        if let Some(path) = &self.token_file {
            if path.exists() {
                match std::fs::read_to_string(path) {
                    Ok(content) => {
                        let trimmed = content.trim();
                        if !trimmed.is_empty() {
                            return trimmed.to_string();
                        }
                    }
                    Err(e) => {
                        tracing::warn!("Failed to read token file at {:?}: {}", path, e);
                    }
                }
            }
        }

        // Default or fallback: generate a random uuid token and notify the user
        let generated = uuid::Uuid::new_v4().to_string();
        info!("No auth token provided. Generated ephemeral token: {}", generated);
        generated
    }

    /// Resolves the session directory path, defaulting to `~/.zed-remote/sessions`.
    pub fn resolve_session_dir(&self) -> PathBuf {
        if let Some(dir) = &self.session_dir {
            dir.clone()
        } else {
            let home = std::env::var("HOME")
                .or_else(|_| std::env::var("USERPROFILE"))
                .unwrap_or_else(|_| ".".to_string());
            PathBuf::from(home).join(".zed-remote").join("sessions")
        }
    }

    /// Resolves the workspace directory, defaulting to the current working directory.
    pub fn resolve_workspace_root(&self) -> PathBuf {
        self.workspace_root
            .clone()
            .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))
    }
}
