//! Native Git repository inspection, staging, committing, and push operations.

use crate::error::{DaemonError, Result};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;
use tokio::process::Command;
use tokio::sync::Mutex;
use tracing::{debug, info};

/// Status of an individual tracked or untracked file in the repository.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitFileStatus {
    pub path: String,
    pub status: String,
    pub staged: bool,
    pub insertions: usize,
    pub deletions: usize,
}

/// Comprehensive repository status summary.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatusResult {
    pub branch: String,
    pub clean: bool,
    pub ahead: usize,
    pub behind: usize,
    pub files: Vec<GitFileStatus>,
}

/// Result of a file diff query.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitDiffResult {
    pub path: String,
    pub diff: String,
    pub insertions: usize,
    pub deletions: usize,
}

/// Result of a commit operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitCommitResult {
    pub commit_hash: String,
    pub branch: String,
    pub summary: String,
}

/// Commit log entry representation for mobile git graph / log inspection.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitCommitInfo {
    pub hash: String,
    pub author: String,
    pub date: String,
    pub decorations: String,
    pub message: String,
}

/// Git operational engine executing asynchronous commands within the workspace root.
#[derive(Clone, Debug)]
pub struct GitEngine {
    workspace_root: PathBuf,
    mutation_lock: Arc<Mutex<()>>,
}

impl GitEngine {
    /// Initializes a GitEngine anchored at `workspace_root`.
    pub fn new(workspace_root: PathBuf) -> Self {
        Self {
            workspace_root,
            mutation_lock: Arc::new(Mutex::new(())),
        }
    }

    /// Helper to execute a git command in the repository workspace.
    async fn run_git(&self, args: &[&str]) -> Result<String> {
        debug!("Executing git {:?}", args);
        let output = Command::new("git")
            .args(args)
            .current_dir(&self.workspace_root)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(DaemonError::Git(format!(
                "git {} failed: {}",
                args.join(" "),
                stderr.trim()
            )));
        }

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    /// Retrieves current Git branch name.
    pub async fn current_branch(&self) -> Result<String> {
        let out = self.run_git(&["rev-parse", "--abbrev-ref", "HEAD"]).await?;
        Ok(out.trim().to_string())
    }

    /// Returns detailed repository status including modified, staged, and untracked files.
    pub async fn status(&self) -> Result<GitStatusResult> {
        let branch = self.current_branch().await.unwrap_or_else(|_| "HEAD".to_string());
        let raw_status = self.run_git(&["status", "--porcelain=v1", "-z"]).await?;

        let mut files = Vec::new();
        let tokens: Vec<&str> = raw_status.split('\0').collect();
        let mut idx = 0;
        while idx < tokens.len() {
            let token = tokens[idx];
            idx += 1;
            if token.len() < 3 {
                continue;
            }
            let index_status = token.chars().nth(0).unwrap_or(' ');
            let worktree_status = token.chars().nth(1).unwrap_or(' ');
            let file_path = &token[3..];

            // In git status -z porcelain, rename (R) and copy (C) records put the new path first, then old path in the next token
            let is_rename_or_copy = index_status == 'R' || worktree_status == 'R' || index_status == 'C' || worktree_status == 'C';
            let old_path = if is_rename_or_copy {
                if idx < tokens.len() && !tokens[idx].is_empty() {
                    let p = tokens[idx].to_string();
                    idx += 1; // consume source pathname token
                    Some(p)
                } else {
                    None
                }
            } else {
                None
            };

            let staged = index_status != ' ' && index_status != '?';
            let status_label = match (index_status, worktree_status) {
                ('?', '?') => "untracked",
                ('A', _) | (_, 'A') => "new",
                ('M', _) | (_, 'M') => "modified",
                ('D', _) | (_, 'D') => "deleted",
                ('R', _) | (_, 'R') => "renamed",
                ('C', _) | (_, 'C') => "copied",
                ('U', _) | (_, 'U') => "conflict",
                _ => "modified",
            };

            if !file_path.is_empty() {
                files.push(GitFileStatus {
                    path: file_path.to_string(),
                    status: status_label.to_string(),
                    staged,
                    insertions: 0,
                    deletions: 0,
                });
            }

            // For renames, also retain the original path so operations such as Unstage All supply both paths
            if let Some(src) = old_path {
                if !src.is_empty() && (index_status == 'R' || worktree_status == 'R') {
                    files.push(GitFileStatus {
                        path: src,
                        status: "renamed-orig".to_string(),
                        staged,
                        insertions: 0,
                        deletions: 0,
                    });
                }
            }
        }

        let is_clean = files.is_empty();

        Ok(GitStatusResult {
            branch,
            clean: is_clean,
            ahead: 0,
            behind: 0,
            files,
        })
    }

    /// Returns unified diff content for a specific file or the entire repository.
    pub async fn diff(&self, path: Option<&str>, staged: bool) -> Result<GitDiffResult> {
        let mut args = vec!["diff"];
        if staged {
            args.push("--cached");
        }
        if let Some(p) = path {
            args.push("--");
            args.push(p);
        }

        let raw_diff = self.run_git(&args).await?;

        let mut insertions = 0;
        let mut deletions = 0;
        for line in raw_diff.lines() {
            if line.starts_with('+') && !line.starts_with("+++") {
                insertions += 1;
            } else if line.starts_with('-') && !line.starts_with("---") {
                deletions += 1;
            }
        }

        Ok(GitDiffResult {
            path: path.unwrap_or("all").to_string(),
            diff: raw_diff,
            insertions,
            deletions,
        })
    }

    /// Stages specific file paths (`git add <path>`).
    pub async fn stage(&self, paths: &[String]) -> Result<()> {
        let _guard = self.mutation_lock.lock().await;
        if paths.is_empty() {
            return Ok(());
        }
        let mut args = vec!["add", "--"];
        let str_paths: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
        args.extend(str_paths);

        self.run_git(&args).await?;
        info!("Staged {} files", paths.len());
        Ok(())
    }

    /// Commits changes with a user-supplied message, optionally staging all changes beforehand.
    pub async fn commit(&self, message: &str, stage_all: bool) -> Result<GitCommitResult> {
        let _guard = self.mutation_lock.lock().await;
        if stage_all {
            self.run_git(&["add", "-A"]).await?;
        }

        self.run_git(&["commit", "-m", message]).await?;

        let hash_raw = self.run_git(&["rev-parse", "--short", "HEAD"]).await?;
        let branch = self.current_branch().await.unwrap_or_else(|_| "HEAD".to_string());

        let commit_hash = hash_raw.trim().to_string();
        info!("Created commit {} on branch {}", commit_hash, branch);

        Ok(GitCommitResult {
            commit_hash,
            branch,
            summary: message.to_string(),
        })
    }

    /// Pushes committed changes to the upstream remote repository.
    pub async fn push(&self, remote: Option<&str>, branch: Option<&str>) -> Result<String> {
        let current = self.current_branch().await.unwrap_or_else(|_| "main".to_string());
        let target_branch = branch.unwrap_or(&current);
        let target_remote = remote.unwrap_or("origin");

        info!("Pushing branch {} to remote {}", target_branch, target_remote);
        let out = self.run_git(&["push", target_remote, target_branch]).await?;
        Ok(out)
    }

    /// Unstages specific files (`git restore --staged <paths>` or `git rm --cached` if no HEAD yet).
    pub async fn unstage(&self, paths: &[String]) -> Result<()> {
        let _guard = self.mutation_lock.lock().await;
        if paths.is_empty() {
            return Ok(());
        }
        let has_head = self.run_git(&["rev-parse", "--verify", "HEAD"]).await.is_ok();
        let mut args = if has_head {
            vec!["restore", "--staged", "--"]
        } else {
            vec!["rm", "--cached", "-r", "--"]
        };
        let str_paths: Vec<&str> = paths.iter().map(|s| s.as_str()).collect();
        args.extend(str_paths);

        self.run_git(&args).await?;
        info!("Unstaged {} files", paths.len());
        Ok(())
    }

    /// Checks out or switches to a branch.
    pub async fn checkout(&self, branch: &str) -> Result<String> {
        let _guard = self.mutation_lock.lock().await;
        let clean_branch = branch.trim();
        if clean_branch.is_empty() {
            return Err(DaemonError::Git("Branch name cannot be empty".to_string()));
        }
        info!("Switching to branch {}", clean_branch);

        // Handle remote tracking branches (e.g. "origin/topic" or "remotes/origin/topic")
        if clean_branch.starts_with("origin/") || clean_branch.starts_with("remotes/origin/") {
            let local_name = clean_branch
                .trim_start_matches("remotes/")
                .trim_start_matches("origin/");
            let local_ref = format!("refs/heads/{}", local_name);
            let has_local = self.run_git(&["rev-parse", "--verify", &local_ref]).await.is_ok();

            if has_local {
                let out = match self.run_git(&["switch", local_name]).await {
                    Ok(o) => o,
                    Err(_) => self.run_git(&["checkout", local_name, "--"]).await?,
                };
                return Ok(out);
            } else {
                let out = match self.run_git(&["switch", "-c", local_name, "--track", clean_branch]).await {
                    Ok(o) => o,
                    Err(_) => self.run_git(&["checkout", "-b", local_name, "--track", clean_branch, "--"]).await?,
                };
                return Ok(out);
            }
        }

        // Branch-only switch with path ambiguity guard
        let out = match self.run_git(&["switch", clean_branch]).await {
            Ok(o) => o,
            Err(_) => self.run_git(&["checkout", clean_branch, "--"]).await?,
        };
        Ok(out)
    }

    /// Retrieves list of all local and remote branches.
    pub async fn branches(&self) -> Result<Vec<String>> {
        let out = self.run_git(&["branch", "-a", "--format=%(refname:short)"]).await?;
        let mut list = Vec::new();
        for line in out.lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() && !list.contains(&trimmed.to_string()) {
                list.push(trimmed.to_string());
            }
        }
        Ok(list)
    }

    /// Retrieves recent commit history formatted for graphical display.
    pub async fn log_graph(&self, limit: usize) -> Result<Vec<GitCommitInfo>> {
        let limit_str = format!("-n{}", limit.max(1));
        let out = self
            .run_git(&["log", &limit_str, "--pretty=format:%h%x09%an%x09%ar%x09%d%x09%s"])
            .await?;

        let mut commits = Vec::new();
        for line in out.lines() {
            let parts: Vec<&str> = line.split('\t').collect();
            if parts.len() >= 5 {
                commits.push(GitCommitInfo {
                    hash: parts[0].to_string(),
                    author: parts[1].to_string(),
                    date: parts[2].to_string(),
                    decorations: parts[3].trim().to_string(),
                    message: parts[4].to_string(),
                });
            } else if !parts.is_empty() && !parts[0].is_empty() {
                commits.push(GitCommitInfo {
                    hash: parts[0].to_string(),
                    author: String::new(),
                    date: String::new(),
                    decorations: String::new(),
                    message: parts.get(1).copied().unwrap_or("").to_string(),
                });
            }
        }
        Ok(commits)
    }
}
