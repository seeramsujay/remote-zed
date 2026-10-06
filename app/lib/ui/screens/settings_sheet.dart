import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/websocket_client.dart';

/// Modal bottom sheet for configuring Tailscale IP, port, and authentication bearer token.
class SettingsSheet extends StatefulWidget {
  final WebSocketClient client;

  const SettingsSheet({super.key, required this.client});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;
  late bool _useTls;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.client.host);
    _portController = TextEditingController(text: widget.client.port.toString());
    _tokenController = TextEditingController(text: widget.client.token);
    _useTls = widget.client.useTls;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _saveAndReconnect() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8443;
    final token = _tokenController.text.trim();

    widget.client.updateConfig(
      host: host,
      port: port,
      token: token,
      useTls: _useTls,
    );

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
            const SizedBox(height: 16),
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
                onPressed: _saveAndReconnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Save & Reconnect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
