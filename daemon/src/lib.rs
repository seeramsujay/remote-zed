//! Zed Remote Host Daemon Library
//!
//! Provides the core architectural components for intercepting the Agent Client Protocol (ACP),
//! serving WebSocket connections over Tailscale, and executing Git and host telemetry operations.

pub mod config;
pub mod error;
pub mod gateway;
pub mod git;
pub mod protocol;
pub mod proxy;
pub mod security;
pub mod session;
pub mod telemetry;

pub use config::Config;
pub use error::{DaemonError, Result};
