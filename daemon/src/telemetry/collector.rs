//! Host hardware metrics collection and system power management routines.

use crate::error::{DaemonError, Result};
use serde::{Deserialize, Serialize};
use sysinfo::System;
use tokio::sync::Mutex;
use tracing::{info, warn};

/// System telemetry report sent to mobile client.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TelemetryResult {
    pub host_name: String,
    pub os: String,
    pub cpu_usage_percent: f32,
    pub memory_used_bytes: u64,
    pub memory_total_bytes: u64,
    pub battery_percent: Option<f32>,
    pub is_charging: Option<bool>,
    pub uptime_seconds: u64,
}

/// Power state action requested by client.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PowerAction {
    Sleep,
    Lock,
    Shutdown,
    Reboot,
}

/// Result of a power state action.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerActionResult {
    pub acknowledged: bool,
    pub message: String,
}

/// Thread-safe system metrics collector.
pub struct TelemetryCollector {
    sys: Mutex<System>,
}

impl TelemetryCollector {
    /// Creates a new `TelemetryCollector` initializing sysinfo data structures.
    pub fn new() -> Self {
        let mut sys = System::new_all();
        sys.refresh_all();
        Self {
            sys: Mutex::new(sys),
        }
    }

    /// Captures a fresh snapshot of host metrics.
    pub async fn collect(&self) -> TelemetryResult {
        let mut sys = self.sys.lock().await;
        sys.refresh_cpu_usage();
        sys.refresh_memory();

        let host_name = System::host_name().unwrap_or_else(|| "unknown-host".to_string());
        let os_name = System::name().unwrap_or_else(|| "unknown-os".to_string());
        let kernel = System::kernel_version().unwrap_or_default();
        let os = format!("{} {}", os_name, kernel).trim().to_string();

        let cpu_usage_percent = sys.global_cpu_info().cpu_usage();
        let memory_used_bytes = sys.used_memory();
        let memory_total_bytes = sys.total_memory();
        let uptime_seconds = System::uptime();

        // Query battery percentage from sysfs on Linux if available
        let (battery_percent, is_charging) = Self::read_linux_battery().await;

        TelemetryResult {
            host_name,
            os,
            cpu_usage_percent,
            memory_used_bytes,
            memory_total_bytes,
            battery_percent,
            is_charging,
            uptime_seconds,
        }
    }

    /// Reads battery status from Linux `/sys/class/power_supply/` if running on a laptop.
    async fn read_linux_battery() -> (Option<f32>, Option<bool>) {
        let capacity_path = std::path::Path::new("/sys/class/power_supply/BAT0/capacity");
        let status_path = std::path::Path::new("/sys/class/power_supply/BAT0/status");

        let percent = if capacity_path.exists() {
            tokio::fs::read_to_string(capacity_path)
                .await
                .ok()
                .and_then(|s| s.trim().parse::<f32>().ok())
        } else {
            None
        };

        let charging = if status_path.exists() {
            tokio::fs::read_to_string(status_path)
                .await
                .ok()
                .map(|s| s.trim().to_lowercase() == "charging")
        } else {
            None
        };

        (percent, charging)
    }

    /// Executes system power state modifications.
    pub async fn execute_power_action(&self, action: PowerAction) -> Result<PowerActionResult> {
        info!("Executing power action: {:?}", action);

        #[cfg(target_os = "linux")]
        {
            let (cmd, args): (&str, &[&str]) = match action {
                PowerAction::Sleep => ("systemctl", &["suspend"]),
                PowerAction::Lock => ("loginctl", &["lock-session"]),
                PowerAction::Shutdown => ("shutdown", &["-h", "now"]),
                PowerAction::Reboot => ("shutdown", &["-r", "now"]),
            };

            let status = tokio::process::Command::new(cmd)
                .args(args)
                .status()
                .await?;

            if status.success() {
                Ok(PowerActionResult {
                    acknowledged: true,
                    message: format!("Power action {:?} dispatched successfully", action),
                })
            } else {
                Err(DaemonError::Telemetry(format!(
                    "Command {} {:?} failed with exit code {:?}",
                    cmd, args, status.code()
                )))
            }
        }

        #[cfg(target_os = "macos")]
        {
            let (cmd, args): (&str, &[&str]) = match action {
                PowerAction::Sleep => ("pmset", &["sleepnow"]),
                PowerAction::Lock => (
                    "pmset",
                    &["displaysleepnow"],
                ),
                PowerAction::Shutdown => ("shutdown", &["-h", "now"]),
                PowerAction::Reboot => ("shutdown", &["-r", "now"]),
            };

            let status = tokio::process::Command::new(cmd)
                .args(args)
                .status()
                .await?;

            if status.success() {
                Ok(PowerActionResult {
                    acknowledged: true,
                    message: format!("Power action {:?} dispatched successfully", action),
                })
            } else {
                Err(DaemonError::Telemetry(format!(
                    "Command {} {:?} failed with exit code {:?}",
                    cmd, args, status.code()
                )))
            }
        }

        #[cfg(not(any(target_os = "linux", target_os = "macos")))]
        {
            warn!("Power action {:?} unsupported on this operating system", action);
            Ok(PowerActionResult {
                acknowledged: false,
                message: "Unsupported operating system for power actions".to_string(),
            })
        }
    }
}
