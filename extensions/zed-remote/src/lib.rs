use zed_extension_api::{
    self as zed, Command, ContextServerId, Extension, Project, Result, SlashCommand,
    SlashCommandOutput, SlashCommandOutputSection,
};

struct ZedRemoteExtension;

impl Extension for ZedRemoteExtension {
    fn new() -> Self {
        Self
    }

    /// Launches the Zed Remote Daemon as an MCP context server when Zed opens.
    fn context_server_command(
        &mut self,
        _context_server_id: &ContextServerId,
        _project: &Project,
    ) -> Result<Command> {
        let binary_path = std::env::var("HOME")
            .map(|h| format!("{}/.local/bin/zed-remote-daemon", h))
            .unwrap_or_else(|_| "/usr/local/bin/zed-remote-daemon".to_string());

        Ok(Command {
            command: binary_path,
            args: vec![
                "--port".to_string(),
                "8443".to_string(),
            ],
            env: Default::default(),
        })
    }

    /// Provides slash command `/bunker` inside Zed Assistant / Agent panel
    /// to display current connection credentials.
    fn complete_slash_command_argument(
        &self,
        _command: SlashCommand,
        _args: Vec<String>,
    ) -> Result<Vec<zed_extension_api::SlashCommandArgumentCompletion>, String> {
        Ok(vec![
            zed_extension_api::SlashCommandArgumentCompletion {
                label: "status".to_string(),
                new_text: "status".to_string(),
                run_upon_completion: true,
            },
            zed_extension_api::SlashCommandArgumentCompletion {
                label: "pair".to_string(),
                new_text: "pair".to_string(),
                run_upon_completion: true,
            },
        ])
    }

    fn run_slash_command(
        &self,
        _command: SlashCommand,
        args: Vec<String>,
        _worktree: Option<&zed::Worktree>,
    ) -> Result<SlashCommandOutput, String> {
        let sub = args.first().map(|s| s.as_str()).unwrap_or("status");
        let text = match sub {
            "pair" => {
                "Run `~/.config/zed-remote/bunker-tunnel.sh` or scan your terminal QR code to pair your mobile phone."
                    .to_string()
            }
            _ => {
                "Zed Remote active. Intercepting ACP agent streams and serving mobile endpoints on port 8443."
                    .to_string()
            }
        };

        Ok(SlashCommandOutput {
            sections: vec![SlashCommandOutputSection {
                range: (0..text.len()).into(),
                label: "Zed Remote Mobile Status".to_string(),
            }],
            text,
        })
    }
}

zed::register_extension!(ZedRemoteExtension);
