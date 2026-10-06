import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/bunker_tunnel_service.dart';
import '../../services/websocket_client.dart';

/// Modal bottom sheet for configuring Tailscale IP or Bunker Mode (DPI/Firewall resistant).
class SettingsSheet extends StatefulWidget {
  final WebSocketClient client;
  final BunkerTunnelService bunkerService;

  const SettingsSheet({
    super.key,
    required this.client,
    required this.bunkerService,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;
  late TextEditingController _bunkerUriController;
  late bool _useTls;
  bool _bunkerMode = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.client.host);
    _portController = TextEditingController(text: widget.client.port.toString());
    _tokenController = TextEditingController(text: widget.client.token);
    _bunkerUriController = TextEditingController();
    _useTls = widget.client.useTls;
    _bunkerMode = widget.bunkerService.isActive;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _bunkerUriController.dispose();
    super.dispose();
  }

  void _saveDirectConnection() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8443;
    final token = _tokenController.text.trim();

    widget.bunkerService.deactivate();
    widget.client.updateConfig(
      host: host,
      port: port,
      token: token,
      useTls: _useTls,
    );

    Navigator.of(context).pop();
  }

  void _applyBunkerPairing() {
    final uriStr = _bunkerUriController.text.trim();
    final creds = BunkerCredentials.fromUri(uriStr);

    if (creds == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid Bunker URI. Must match: zed-remote://pair?...'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    widget.bunkerService.activate(creds);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_outlined, color: AppTheme.primaryAccent),
                const SizedBox(width: 8),
                const Text(
                  'Connection Settings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Mode Selector
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Direct / Mesh', style: TextStyle(fontSize: 12)),
                  icon: Icon(Icons.lan_outlined, size: 16),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Bunker (DPI-Proof)', style: TextStyle(fontSize: 12)),
                  icon: Icon(Icons.shield_outlined, size: 16),
                ),
              ],
              selected: {_bunkerMode},
              onSelectionChanged: (set) {
                setState(() => _bunkerMode = set.first);
              },
            ),
            const SizedBox(height: 16),

            if (_bunkerMode) ...[
              // Bunker Mode configuration
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x153B82F6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x403B82F6)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: AppTheme.primaryAccent),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bypasses Fortinet, corporate DPI firewalls, and hostel restrictions using SSH over port 443 with AES-256-GCM zero-knowledge rendezvous.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Pairing URI (from terminal QR code):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _bunkerUriController,
                decoration: InputDecoration(
                  hintText: 'zed-remote://pair?topic=...&key=...',
                  hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (widget.bunkerService.isActive) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.check_circle, size: 16, color: AppTheme.success),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Active Tunnel: ${widget.bunkerService.lastTunnelUrl ?? "Resolving..."}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.success, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Pair & Start Bunker Auto-Sync'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _applyBunkerPairing,
                ),
              ),
            ] else ...[
              // Standard Direct / Tailscale configuration
              const Text('Host / Tailscale IP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  hintText: '100.x.y.z or hostname',
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Port', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '8443',
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Bearer Token', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              TextField(
                controller: _tokenController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Secret authorization token',
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use TLS (wss://)', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Enable if using TLS certificates on Tailscale',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                value: _useTls,
                onChanged: (val) => setState(() => _useTls = val),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveDirectConnection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Save & Reconnect'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
