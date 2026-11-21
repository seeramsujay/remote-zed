//! WebSocket handshake authentication, timing-safe token verification, and brute-force protection.

use crate::security::SecurityGuard;
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::warn;

/// Authenticator verifying client credentials with rate limiting and constant-time comparison.
#[derive(Clone)]
pub struct AuthValidator {
    secret_token: String,
    failed_attempts: Arc<RwLock<HashMap<IpAddr, (u32, Instant)>>>,
}

impl AuthValidator {
    /// Creates a new validator holding the secret token.
    pub fn new(secret_token: String) -> Self {
        Self {
            secret_token,
            failed_attempts: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Returns the configured secret token.
    pub fn token(&self) -> &str {
        &self.secret_token
    }

    /// Verifies if a peer IP is currently locked out due to excessive failed attempts.
    pub async fn is_rate_limited(&self, ip: IpAddr) -> bool {
        let lock = self.failed_attempts.read().await;
        if let Some((count, last_fail)) = lock.get(&ip) {
            if *count >= 5 {
                // Lockout duration: 15 minutes
                if last_fail.elapsed() < Duration::from_secs(900) {
                    return true;
                }
            }
        }
        false
    }

    /// Validates token with rate limiting and constant-time comparison.
    pub async fn validate_peer(&self, presented: &str, ip: IpAddr) -> bool {
        if self.is_rate_limited(ip).await {
            warn!("Blocked connection attempt from rate-limited IP: {}", ip);
            return false;
        }

        let trimmed = presented.trim();
        let valid = SecurityGuard::verify_token(&self.secret_token, trimmed);
        let mut lock = self.failed_attempts.write().await;
        if valid {
            // Reset failed counter on successful auth
            lock.remove(&ip);
            true
        } else {
            let entry = lock.entry(ip).or_insert((0, Instant::now()));
            entry.0 += 1;
            entry.1 = Instant::now();
            warn!(
                "Failed auth attempt from {} (attempt {}/5)",
                ip, entry.0
            );
            if entry.0 >= 5 {
                warn!("🚨 IP {} temporarily locked out for 15 minutes due to 5 consecutive auth failures", ip);
            }
            false
        }
    }

    /// Verifies that a presented token string matches the configured secret token.
    pub fn validate(&self, presented: &str) -> bool {
        let trimmed = presented.trim();
        let valid = SecurityGuard::verify_token(&self.secret_token, trimmed);
        if !valid {
            warn!("Rejected unauthorized token verification attempt");
        }
        valid
    }

    /// Extracts token from an HTTP Authorization header value (e.g. `Bearer <TOKEN>`).
    pub fn extract_bearer_token(header_value: &str) -> Option<&str> {
        let parts: Vec<&str> = header_value.split_whitespace().collect();
        if parts.len() == 2 && parts[0].eq_ignore_ascii_case("bearer") {
            Some(parts[1])
        } else {
            None
        }
    }
}
