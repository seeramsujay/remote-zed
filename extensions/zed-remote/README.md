# Zed Remote Dev Extension

A native Zed Dev Extension that integrates **Zed Remote** directly into Zed editor.

## Features

- **MCP Context Server**: Registers `zed-remote` as a background MCP context server so Zed automatically launches and supervises `zed-remote-daemon`.
- **Slash Commands**: Adds `/bunker status` and `/bunker pair` to Zed's Assistant/Agent panel.
- **Zero-Compile Setup**: Works with official Zed releases without recompiling Zed from source.

## How to Install in Zed

1. Open Zed.
2. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`).
3. Type and select `zed: install dev extension`.
4. Select this directory: `extensions/zed-remote`.

Alternatively, run:
```bash
./tools/install-extension.sh
```
