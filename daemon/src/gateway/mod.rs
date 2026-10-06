//! Network gateway and WebSocket connection handling.

pub mod auth;
pub mod server;

pub use auth::AuthValidator;
pub use server::WebSocketGateway;
