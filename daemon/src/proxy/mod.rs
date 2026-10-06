//! Asynchronous stdio proxy and process supervision module.

pub mod process;
pub mod router;

pub use process::AgentSubprocess;
pub use router::{MessageRouter, PendingPermission};
