//! Security guardrails, command blocklists, and workspace boundary checks.

use crate::error::{DaemonError, Result};
use std::path::{Path, PathBuf};
use subtle::ConstantTimeEq;
use tracing::warn;

/// Security validator enforcing execution boundaries and command policies.
#[derive(Clone, Debug)]
pub struct SecurityGuard {
    blocked_commands: Vec<String>,
    workspace_root: PathBuf,
}

impl SecurityGuard {
    /// Constructs a security validator with default or configured blocklists.
    pub fn new(workspace_root: PathBuf, mut blocked_commands: Vec<String>) -> Self {
        // Enforce baseline destructive command blocklist
        let defaults = vec![
            "rm -rf /".to_string(),
            ":(){ :|:& };:".to_string(),
            "mkfs".to_string(),
            "dd if=".to_string(),
            "> /dev/sda".to_string(),
        ];

        for default_cmd in defaults {
            if !blocked_commands.contains(&default_cmd) {
                blocked_commands.push(default_cmd);
            }
        }

        Self {
            blocked_commands,
            workspace_root,
        }
    }

    /// Verifies if a shell command string contains any blocked command patterns.
    pub fn check_command(&self, command_str: &str) -> Result<()> {
        let normalized = command_str.to_lowercase();
        for blocked in &self.blocked_commands {
            if normalized.contains(&blocked.to_lowercase()) {
                warn!("Blocked malicious command pattern: '{}' in '{}'", blocked, command_str);
                return Err(DaemonError::Security(format!(
                    "Command contains prohibited pattern '{}'",
                    blocked
                )));
            }
        }
        Ok(())
    }

    /// Validates that a file path remains within the active workspace root to prevent path traversal.
    pub fn check_path(&self, target_path: &Path) -> Result<PathBuf> {
        let canonical_root = self
            .workspace_root
            .canonicalize()
            .unwrap_or_else(|_| self.workspace_root.clone());

        let target_full = if target_path.is_relative() {
            self.workspace_root.join(target_path)
        } else {
            target_path.to_path_buf()
        };

        let canonical_target = target_full
            .canonicalize()
            .unwrap_or_else(|_| target_full.clone());

        if !canonical_target.starts_with(&canonical_root) {
            warn!(
                "Path traversal detected: target {:?} outside workspace root {:?}",
                canonical_target, canonical_root
            );
            return Err(DaemonError::Security(format!(
                "Target path {:?} is outside workspace root",
                target_path
            )));
        }

        Ok(canonical_target)
    }

    /// Performs constant-time token comparison to prevent timing side-channel attacks.
    pub fn verify_token(expected: &str, provided: &str) -> bool {
        let expected_bytes = expected.as_bytes();
        let provided_bytes = provided.as_bytes();

        if expected_bytes.len() != provided_bytes.len() {
            return false;
        }

        expected_bytes.ct_eq(provided_bytes).into()
    }
}
