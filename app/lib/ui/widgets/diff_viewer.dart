import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/git_models.dart';

/// Interactive modal/dialog presenting unified diffs with line-level color highlighting.
class DiffViewerDialog extends StatelessWidget {
  final GitDiffResult diffResult;

  const DiffViewerDialog({super.key, required this.diffResult});

  @override
  Widget build(BuildContext context) {
    final lines = diffResult.diff.split('\n');

    return Dialog(
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.difference_outlined, size: 20, color: AppTheme.primaryAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diffResult.path,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '+${diffResult.insertions} ',
                  style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold),
                ),
                Text(
                  '-${diffResult.deletions}',
                  style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Diff content
          Expanded(
            child: lines.isEmpty || diffResult.diff.trim().isEmpty
                ? const Center(
                    child: Text('No diff available', style: TextStyle(color: AppTheme.textSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      Color? bgColor;
                      Color textColor = AppTheme.textPrimary;

                      if (line.startsWith('+') && !line.startsWith('+++')) {
                        bgColor = const Color(0x2210B981);
                        textColor = const Color(0xFF34D399);
                      } else if (line.startsWith('-') && !line.startsWith('---')) {
                        bgColor = const Color(0x22EF4444);
                        textColor = const Color(0xFFF87171);
                      } else if (line.startsWith('@@')) {
                        bgColor = const Color(0x223B82F6);
                        textColor = AppTheme.primaryAccent;
                      }

                      return Container(
                        color: bgColor,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: textColor,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
