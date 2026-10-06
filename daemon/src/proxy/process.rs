//! Target AI agent child process supervisor.

use crate::error::{DaemonError, Result};
use std::process::Stdio;
use tokio::process::{Child, ChildStdin, ChildStdout, Command};
use tracing::info;

/// Encapsulates the running child process and its standard I/O channels.
pub struct AgentSubprocess {
    pub child: Child,
    pub stdin: ChildStdin,
    pub stdout: ChildStdout,
}

impl AgentSubprocess {
    /// Spawns the target agent executable with configured arguments and pipes.
    pub fn spawn(command: &str, args: &str) -> Result<Self> {
        info!("Spawning target AI agent: {} {}", command, args);

        let parsed_args: Vec<&str> = if args.trim().is_empty() {
            Vec::new()
        } else {
            args.split_whitespace().collect()
        };

        let mut child = Command::new(command)
            .args(&parsed_args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|e| {
                DaemonError::Subprocess(format!(
                    "Failed to spawn target agent '{}': {}",
                    command, e
                ))
            })?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| DaemonError::Subprocess("Failed to capture child stdin".into()))?;

        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| DaemonError::Subprocess("Failed to capture child stdout".into()))?;

        Ok(Self {
            child,
            stdin,
            stdout,
        })
    }
}
