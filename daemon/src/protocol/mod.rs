//! Protocol codec, JSON-RPC primitives, and ACP message structures.

pub mod acp;
pub mod rpc;

pub use acp::*;
pub use rpc::*;

/// Splits an incoming byte stream into Newline-Delimited JSON (NDJSON) string frames.
pub fn format_ndjson_line(message: &str) -> String {
    let mut trimmed = message.trim().to_string();
    trimmed.push('\n');
    trimmed
}
