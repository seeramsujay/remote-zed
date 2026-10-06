import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/acp_models.dart';

/// Modal dialog presented when the AI agent requests authorization for a tool call (e.g. terminal execution).
class PermissionDialog extends StatelessWidget {
  final PermissionRequest request;
  final VoidCallback onApprove;
  final ValueChanged<String> onReject;

  const PermissionDialog({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final command = request.parameters['command'] as String?;
    final path = request.parameters['path'] as String?;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.warning, width: 1.5),
      ),
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: AppTheme.warning, size: 24),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tool Authorization Required',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The agent requests permission to execute:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                request.toolName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryAccent,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (command != null) ...[
              const Text('Command:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.amberAccent),
                ),
              ),
            ] else if (path != null) ...[
              const Text('Target Path:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  path,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.greenAccent),
                ),
              ),
            ] else ...[
              const Text('Parameters:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(request.parameters),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => onReject('Rejected from mobile'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
          child: const Text('Reject'),
        ),
        ElevatedButton(
          onPressed: onApprove,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
          ),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}
