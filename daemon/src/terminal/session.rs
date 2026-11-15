//! Interactive mobile terminal engine and remote filesystem explorer.

use crate::error::{DaemonError, Result};
use crate::security::SecurityGuard;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;
use tokio::fs::{create_dir_all, read_dir};
use tokio::process::Command;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// File entry returned when browsing directories.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size_bytes: u64,
    pub modified_epoch_secs: u64,
}

/// Result of a shell execution turn.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalExecResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
    pub cwd: String,
}

/// Directory contents query result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FsListResult {
    pub current_path: String,
    pub parent_path: Option<String>,
    pub entries: Vec<FileEntry>,
}

/// Interactive terminal and file management supervisor.
#[derive(Clone)]
pub struct TerminalManager {
    cwd: Arc<RwLock<PathBuf>>,
    security: SecurityGuard,
}

impl TerminalManager {
    /// Initializes a `TerminalManager` starting in `initial_cwd`.
    pub fn new(initial_cwd: PathBuf, security: SecurityGuard) -> Self {
        Self {
            cwd: Arc::new(RwLock::new(initial_cwd)),
            security,
        }
    }

    /// Returns the current working directory as an absolute string.
    pub async fn get_cwd(&self) -> String {
        self.cwd.read().await.to_string_lossy().to_string()
    }

    /// Sets the active directory, resolving relative paths.
    pub async fn set_cwd(&self, target: &Path) -> Result<String> {
        let current = self.cwd.read().await.clone();
        let candidate = if target.is_relative() {
            current.join(target)
        } else {
            target.to_path_buf()
        };

        let canonical = candidate.canonicalize().map_err(|e| {
            DaemonError::Io(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("Directory {:?} not found: {}", candidate, e),
            ))
        })?;

        if !canonical.is_dir() {
            return Err(DaemonError::Io(std::io::Error::new(
                std::io::ErrorKind::NotADirectory,
                format!("{:?} is not a directory", canonical),
            )));
        }

        let mut lock = self.cwd.write().await;
        *lock = canonical.clone();
        info!("Updated terminal cwd to: {:?}", canonical);

        // Tell desktop Zed GUI to open this workspace folder if zed is in PATH
        let path_for_zed = canonical.clone();
        tokio::spawn(async move {
            let _ = Command::new("zed")
                .arg(&path_for_zed)
                .spawn();
        });

        Ok(canonical.to_string_lossy().to_string())
    }

    /// Executes an interactive shell command string within the active terminal working directory.
    pub async fn exec(&self, command_line: &str) -> Result<TerminalExecResult> {
        let trimmed = command_line.trim();
        debug!("Terminal exec: '{}'", trimmed);

        // Security check
        self.security.check_command(trimmed)?;

        // Intercept built-in 'cd' command to update stateful cwd
        if trimmed == "cd" || trimmed.starts_with("cd ") {
            let target_arg = if trimmed == "cd" {
                std::env::var("HOME").unwrap_or_else(|_| ".".to_string())
            } else {
                trimmed[3..].trim().to_string()
            };

            // Remove quotes if present
            let clean_arg = target_arg.trim_matches('\'').trim_matches('"');
            match self.set_cwd(Path::new(clean_arg)).await {
                Ok(new_cwd) => {
                    return Ok(TerminalExecResult {
                        stdout: String::new(),
                        stderr: String::new(),
                        exit_code: 0,
                        cwd: new_cwd,
                    });
                }
                Err(e) => {
                    let cur = self.get_cwd().await;
                    return Ok(TerminalExecResult {
                        stdout: String::new(),
                        stderr: format!("cd: {}\n", e),
                        exit_code: 1,
                        cwd: cur,
                    });
                }
            }
        }

        let current_dir = self.cwd.read().await.clone();

        // Run in bash with pipe captures
        let output = Command::new("bash")
            .arg("-c")
            .arg(trimmed)
            .current_dir(&current_dir)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        let exit_code = output.status.code().unwrap_or(-1);

        Ok(TerminalExecResult {
            stdout,
            stderr,
            exit_code,
            cwd: current_dir.to_string_lossy().to_string(),
        })
    }

    /// Lists the contents of a directory. Defaults to active terminal `cwd`.
    pub async fn list_directory(&self, path_opt: Option<&str>) -> Result<FsListResult> {
        let current_cwd = self.cwd.read().await.clone();
        let target_path = if let Some(p) = path_opt {
            let p_path = Path::new(p);
            if p_path.is_relative() {
                current_cwd.join(p_path)
            } else {
                p_path.to_path_buf()
            }
        } else {
            current_cwd
        };

        let canonical = target_path.canonicalize().map_err(|e| {
            DaemonError::Io(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("Path {:?} not found: {}", target_path, e),
            ))
        })?;

        let mut entries = Vec::new();
        let mut dir_reader = read_dir(&canonical).await?;

        while let Ok(Some(entry)) = dir_reader.next_entry().await {
            let name = entry.file_name().to_string_lossy().to_string();
            // Skip hidden entries if desired, or keep them
            let meta = entry.metadata().await.ok();
            let is_dir = meta.as_ref().map(|m| m.is_dir()).unwrap_or(false);
            let size_bytes = meta.as_ref().map(|m| m.len()).unwrap_or(0);
            let modified = meta
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
                .unwrap_or(0);

            entries.push(FileEntry {
                name,
                path: entry.path().to_string_lossy().to_string(),
                is_dir,
                size_bytes,
                modified_epoch_secs: modified,
            });
        }

        // Sort: directories first, then alphabetical
        entries.sort_by(|a, b| {
            if a.is_dir != b.is_dir {
                b.is_dir.cmp(&a.is_dir)
            } else {
                a.name.to_lowercase().cmp(&b.name.to_lowercase())
            }
        });

        let parent = canonical.parent().map(|p| p.to_string_lossy().to_string());

        Ok(FsListResult {
            current_path: canonical.to_string_lossy().to_string(),
            parent_path: parent,
            entries,
        })
    }

    /// Creates a new directory.
    pub async fn create_directory(&self, path_str: &str) -> Result<String> {
        let current_cwd = self.cwd.read().await.clone();
        let target = Path::new(path_str);
        let full_path = if target.is_relative() {
            current_cwd.join(target)
        } else {
            target.to_path_buf()
        };

        create_dir_all(&full_path).await?;
        info!("Created directory at {:?}", full_path);
        Ok(full_path.to_string_lossy().to_string())
    }
}
