//! Zed Remote Host Daemon Library
//!
//! Provides the core architectural components for intercepting the Agent Client Protocol (ACP),
//! serving WebSocket connections over Tailscale or Bunker Tunnel, and executing Git, Terminal,
//! and host telemetry operations.

#![allow(
    clippy::too_many_arguments,
    clippy::result_large_err,
    clippy::new_without_default
)]

pub mod config;
pub mod error;
pub mod gateway;
pub mod git;
pub mod protocol;
pub mod proxy;
pub mod security;
pub mod session;
pub mod telemetry;
pub mod terminal;

pub use config::Config;
pub use error::{DaemonError, Result};
