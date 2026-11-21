//! Security guardrails, command blocklists, and workspace boundary checks.

use crate::error::{DaemonError, Result};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use subtle::ConstantTimeEq;
use tokio::sync::RwLock;
use tracing::{info, warn};

/// Security validator enforcing execution boundaries and command policies.
#[derive(Clone, Debug)]
pub struct SecurityGuard {
    blocked_commands: Vec<String>,
    workspace_root: PathBuf,
    trusted_roots: Arc<RwLock<Vec<PathBuf>>>,
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
            "sudo ".to_string(),
            "su -".to_string(),
            "curl | bash".to_string(),
            "curl | sh".to_string(),
            "wget | bash".to_string(),
            "wget | sh".to_string(),
            "/dev/tcp/".to_string(),
        ];

        for default_cmd in defaults {
            if !blocked_commands.contains(&default_cmd) {
                blocked_commands.push(default_cmd);
            }
        }

        // Initialize trusted roots with workspace root, /dev/shm, and ~/Projects
        let mut initial_trusted = vec![
            workspace_root.clone(),
            PathBuf::from("/dev/shm"),
        ];

        if let Ok(home) = std::env::var("HOME") {
            let projects = PathBuf::from(home).join("Projects");
            if !initial_trusted.contains(&projects) {
                initial_trusted.push(projects);
            }
        }

        Self {
            blocked_commands,
            workspace_root,
            trusted_roots: Arc::new(RwLock::new(initial_trusted)),
        }
    }

    /// Dynamically trusts an additional directory root requested by phone or user.
    pub async fn trust_path(&self, path: PathBuf) {
        let canonical = path.canonicalize().unwrap_or_else(|_| path.clone());
        let mut roots = self.trusted_roots.write().await;
        if !roots.contains(&canonical) {
            info!("Phone explicitly trusted directory boundary: {:?}", canonical);
            roots.push(canonical);
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

    /// Checks if a path targets sensitive host system credentials or configurations.
    pub fn is_sensitive_path(path: &Path) -> bool {
        let path_str = path.to_string_lossy().to_lowercase();
        let sensitive = [
            ".ssh",
            ".gnupg",
            ".aws",
            "/etc/shadow",
            "/etc/sudoers",
            "/etc/passwd",
            "/root",
        ];
        sensitive.iter().any(|s| path_str.contains(s))
    }

    /// Validates that a file path remains within trusted workspace boundaries.
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

        // Strictly prohibit access to host secrets / sensitive credentials
        if Self::is_sensitive_path(&canonical_target) {
            warn!("Rejected access to sensitive system path: {:?}", canonical_target);
            return Err(DaemonError::Security(format!(
                "Access to sensitive path {:?} is strictly prohibited",
                target_path
            )));
        }

        if canonical_target.starts_with(&canonical_root) {
            return Ok(canonical_target);
        }

        // Check if allowed by trusted roots
        if let Ok(roots) = self.trusted_roots.try_read() {
            for trusted in roots.iter() {
                let canon_trusted = trusted.canonicalize().unwrap_or_else(|_| trusted.clone());
                if canonical_target.starts_with(&canon_trusted) {
                    return Ok(canonical_target);
                }
            }
        }

        warn!(
            "Path traversal detected: target {:?} outside trusted roots",
            canonical_target
        );
        Err(DaemonError::Security(format!(
            "Target path {:?} is outside trusted workspace boundaries",
            target_path
        )))
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
