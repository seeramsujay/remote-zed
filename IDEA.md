# IDEA: Zed Remote Protocol Interception & Mobile Control

## Motivation

When working away from your main desk—whether in a hostel, commuting, or away on travel—your primary laptop often remains running at your desk with active internet connectivity. Modern coding workflows increasingly rely on autonomous AI agents (such as AntiGravity running in Zed) to execute multi-step refactoring, write tests, and run terminal commands.

However, existing remote development solutions have significant drawbacks:
- **Graphical Remote Desktop (VNC/RDP)**: Consumes massive bandwidth, suffers high latency on mobile connections, and scales poorly to small phone screens.
- **VS Code Remote / Remote SSH**: Requires heavy editor runtimes on mobile, complex terminal setups, or full IDE interfaces poorly optimized for mobile touch inputs.

Zed is an ultra-fast, open-source code editor written in Rust. It natively communicates with AI agents via the **Agent Client Protocol (ACP)** over standard I/O pipes using JSON-RPC 2.0.

## Core Product Concept

Instead of streaming standard desktop pixels or rendering a full text editor on mobile, **Zed Remote** decouples AI agent control and repository state management from desktop visual rendering.

By proxying the ACP protocol stream, Zed Remote allows a phone to function as a lightweight, interactive companion terminal:

1. **Left Half (Agent Interface)**: Chat with the AI agent, view token-by-token reasoning, and approve tool execution requests (e.g., approving terminal execution or file edits).
2. **Right Half (Repository Control)**: View uncommitted file changes, review structural code diffs, stage files, write commit messages, and push changes to GitHub/GitLab.

## Key Value Proposition

- **Zero-Touch Laptop Operation**: Leave your laptop powered on in your hostel/desk and leave. You can send prompts, approve terminal commands, and commit code entirely from your phone.
- **Protocol-Level Efficiency**: Transmits structured JSON payloads instead of video streams or full text buffers, conserving mobile data and reducing latency.
- **Human-in-the-Loop Safety**: Keeps the user in full control of agent actions by forwarding tool execution prompts directly to mobile lock-screen notifications.
