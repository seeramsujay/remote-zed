//! Hardware metrics and operating system diagnostics.

pub mod collector;

pub use collector::{PowerAction, PowerActionResult, TelemetryCollector, TelemetryResult};
