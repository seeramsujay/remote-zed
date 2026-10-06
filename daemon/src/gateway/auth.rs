//! WebSocket handshake authentication and timing-safe token verification.

use crate::security::SecurityGuard;
use tracing::warn;

/// Authenticator verifying client credentials during the WebSocket handshake.
#[derive(Clone)]
pub struct AuthValidator {
    secret_token: String,
}

impl AuthValidator {
    /// Creates a new validator holding the secret token.
    pub fn new(secret_token: String) -> Self {
        Self { secret_token }
    }

    /// Verifies that a presented token string matches the configured secret token.
    pub fn validate(&self, presented: &str) -> bool {
        let trimmed = presented.trim();
        let valid = SecurityGuard::verify_token(&self.secret_token, trimmed);
        if !valid {
            warn!("Rejected unauthorized WebSocket connection attempt");
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
