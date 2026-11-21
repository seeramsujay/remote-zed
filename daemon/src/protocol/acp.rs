//! Agent Client Protocol (ACP) typed data models and message structures.

use serde::{Deserialize, Serialize};

/// Client capabilities declared during the `initialize` handshake.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ClientCapabilities {
    #[serde(default)]
    pub fs: Option<FsCapabilities>,
    #[serde(default)]
    pub terminal: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FsCapabilities {
    #[serde(default)]
    pub read_text_file: Option<bool>,
    #[serde(default)]
    pub write_text_file: Option<bool>,
}

/// Parameters for the `initialize` method.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InitializeParams {
    pub protocol_version: u32,
    #[serde(default)]
    pub client_capabilities: Option<ClientCapabilities>,
}

/// Content element inside a prompt or message turn.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ContentBlock {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "image")]
    Image { data: String, mime_type: String },
}

/// Parameters for submitting a prompt turn via `session/prompt`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PromptParams {
    pub session_id: String,
    pub prompt: String,
}

/// Detailed update type carried by `session/update` notifications.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "sessionUpdateType")]
pub enum SessionUpdatePayload {
    #[serde(rename = "agent_message_chunk")]
    AgentMessageChunk { content: TextChunk },
    #[serde(rename = "agent_thought_chunk")]
    AgentThoughtChunk { content: TextChunk },
    #[serde(rename = "tool_call_started")]
    ToolCallStarted { tool_call: ToolCallDescriptor },
    #[serde(rename = "tool_call_completed")]
    ToolCallCompleted {
        tool_call_id: String,
        result: serde_json::Value,
    },
    #[serde(rename = "turn_completed")]
    TurnCompleted { stop_reason: Option<String> },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextChunk {
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCallDescriptor {
    pub tool_call_id: String,
    pub name: String,
    #[serde(default)]
    pub parameters: serde_json::Value,
}

/// Parameters for incoming `session/update` notifications.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionUpdateParams {
    pub session_id: String,
    pub update: SessionUpdatePayload,
}

/// Parameters sent by the agent in `session/request_permission`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestPermissionParams {
    pub session_id: String,
    pub tool_call: ToolCallDescriptor,
}

/// User's decision responding to a permission request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PermissionDecisionResult {
    pub decision: PermissionDecision,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PermissionDecision {
    Approved,
    Rejected,
    Modified,
}
