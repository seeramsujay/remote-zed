//! Main executable entrypoint for `zed-remote-daemon`.
//!
//! Spawns the target AI agent process, binds the WebSocket server, and manages
//! the bidirectional message routing loop.

use clap::Parser;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{broadcast, mpsc};
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

use zed_remote_daemon::config::Config;
use zed_remote_daemon::gateway::{AuthValidator, WebSocketGateway};
use zed_remote_daemon::git::GitEngine;
use zed_remote_daemon::proxy::{AgentSubprocess, MessageRouter};
use zed_remote_daemon::security::SecurityGuard;
use zed_remote_daemon::session::SessionManager;
use zed_remote_daemon::telemetry::TelemetryCollector;
use zed_remote_daemon::terminal::TerminalManager;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize logging to stderr (leaving stdout completely clean for Zed JSON-RPC)
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    tracing_subscriber::fmt()
        .with_env_filter(env_filter)
        .with_writer(std::io::stderr)
        .init();

    info!("Starting zed-remote-daemon v{}", env!("CARGO_PKG_VERSION"));

    let config = Config::parse();
    let token = config.resolve_token();
    let session_dir = config.resolve_session_dir();
    let workspace_root = config.resolve_workspace_root();

    let bind_addr: SocketAddr = format!("{}:{}", config.bind_host, config.port).parse()?;
    info!("Target agent: {} {}", config.target_command, config.target_args);
    info!("Workspace root: {:?}", workspace_root);
    info!("Session logs: {:?}", session_dir);

    // Initialize subsystems
    let session_manager = SessionManager::new(session_dir);
    let security = SecurityGuard::new(workspace_root.clone(), config.blocked_commands.clone());
    let git = GitEngine::new(workspace_root.clone());
    let telemetry = Arc::new(TelemetryCollector::new());
    let terminal = Arc::new(TerminalManager::new(workspace_root.clone(), security.clone()));
    let auth = AuthValidator::new(token);

    // Spawn child agent process
    let mut agent_proc = AgentSubprocess::spawn(&config.target_command, &config.target_args)?;

    // Channel creation
    let (mobile_broadcast_tx, _) = broadcast::channel::<String>(1024);
    let (agent_stdin_tx, mut agent_stdin_rx) = mpsc::channel::<String>(512);
    let (zed_stdout_tx, mut zed_stdout_rx) = mpsc::channel::<String>(512);

    let router = MessageRouter::new(
        mobile_broadcast_tx,
        agent_stdin_tx,
        zed_stdout_tx,
        session_manager.clone(),
        security,
    );

    // Task 1: Write to agent stdin
    let mut child_stdin = agent_proc.stdin;
    tokio::spawn(async move {
        while let Some(line) = agent_stdin_rx.recv().await {
            if let Err(e) = child_stdin.write_all(line.as_bytes()).await {
                error!("Error writing to agent stdin: {}", e);
                break;
            }
            let _ = child_stdin.flush().await;
        }
    });

    // Task 2: Read from agent stdout and pass to router
    let child_stdout = agent_proc.stdout;
    let router_for_agent_out = router.clone();
    tokio::spawn(async move {
        let mut reader = BufReader::new(child_stdout).lines();
        while let Ok(Some(line)) = reader.next_line().await {
            router_for_agent_out.handle_agent_output(&line).await;
        }
    });

    // Task 3: Read from Zed stdin (host process stdin) and pass to router
    let router_for_zed_in = router.clone();
    tokio::spawn(async move {
        let stdin = tokio::io::stdin();
        let mut reader = BufReader::new(stdin).lines();
        while let Ok(Some(line)) = reader.next_line().await {
            router_for_zed_in.handle_zed_input(&line).await;
        }
    });

    // Task 4: Write to Zed stdout (host process stdout)
    tokio::spawn(async move {
        let mut stdout = tokio::io::stdout();
        while let Some(line) = zed_stdout_rx.recv().await {
            if let Err(e) = stdout.write_all(line.as_bytes()).await {
                error!("Error writing to Zed stdout: {}", e);
                break;
            }
            let _ = stdout.flush().await;
        }
    });

    // Task 5: Run WebSocket Gateway
    let gateway = WebSocketGateway::new(
        bind_addr,
        auth,
        router.clone(),
        session_manager,
        git,
        telemetry,
        terminal,
    );

    tokio::spawn(async move {
        if let Err(e) = gateway.run().await {
            error!("WebSocket gateway error: {}", e);
        }
    });

    // Wait for exit or cancellation signal
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            info!("Received Ctrl+C, shutting down daemon gracefully...");
        }
        status = agent_proc.child.wait() => {
            info!("Target agent subprocess exited: {:?}", status);
        }
    }

    Ok(())
}
