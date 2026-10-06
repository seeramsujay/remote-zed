//! Terminal execution and file explorer subsystem.

pub mod session;

pub use session::{FileEntry, FsListResult, TerminalExecResult, TerminalManager};
