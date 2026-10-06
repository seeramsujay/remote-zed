import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../models/git_models.dart';
import '../../state/git_state.dart';
import 'diff_viewer.dart';

/// Control panel for inspecting repository state, staging files, reviewing diffs, and committing.
class RepositoryPanel extends StatefulWidget {
  const RepositoryPanel({super.key});

  @override
  State<RepositoryPanel> createState() => _RepositoryPanelState();
}

class _RepositoryPanelState extends State<RepositoryPanel> {
  final TextEditingController _commitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GitState>().refreshStatus();
    });
  }

  @override
  void dispose() {
    _commitController.dispose();
    super.dispose();
  }

  void _showDiff(BuildContext context, GitState gitState, String? path) async {
    await gitState.loadDiff(path);
    if (!mounted) return;
    if (gitState.selectedDiff != null) {
      showDialog(
        context: context,
        builder: (_) => DiffViewerDialog(diffResult: gitState.selectedDiff!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gitState = context.watch<GitState>();
    final status = gitState.status;

    return RefreshIndicator(
      onRefresh: () => gitState.refreshStatus(),
      color: AppTheme.primary,
      child: Column(
        children: [
          // Branch header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppTheme.surface,
            child: Row(
              children: [
                const Icon(Icons.fork_right, size: 18, color: AppTheme.primaryAccent),
                const SizedBox(width: 6),
                Text(
                  status?.branch ?? 'HEAD',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                if (status != null && !status.clean) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.difference_outlined, size: 16),
                    label: const Text('Full Diff', style: TextStyle(fontSize: 12)),
                    onPressed: () => _showDiff(context, gitState, null),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh Status',
                  onPressed: gitState.isLoading ? null : () => gitState.refreshStatus(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // File status list
          Expanded(
            child: gitState.isLoading && status == null
                ? const Center(child: CircularProgressIndicator())
                : status == null || status.clean
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 48, color: AppTheme.success.withOpacity(0.6)),
                            const SizedBox(height: 12),
                            const Text(
                              'Working Tree Clean',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'No uncommitted changes in host workspace.',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: status.files.length,
                        itemBuilder: (context, index) {
                          final file = status.files[index];
                          final isSelected = gitState.selectedFiles.contains(file.path);

                          return ListTile(
                            dense: true,
                            leading: Checkbox(
                              value: isSelected,
                              activeColor: AppTheme.primary,
                              onChanged: (_) => gitState.toggleFileSelection(file.path),
                            ),
                            title: Text(
                              file.path,
                              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              file.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(file.status),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.visibility_outlined, size: 18),
                              tooltip: 'View Diff',
                              onPressed: () => _showDiff(context, gitState, file.path),
                            ),
                          );
                        },
                      ),
          ),

          // Staging & Commit action bar
          if (status != null && !status.clean)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: gitState.toggleSelectAll,
                        child: Text(
                          gitState.selectedFiles.length == status.files.length ? 'Deselect All' : 'Select All',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: gitState.selectedFiles.isEmpty ? null : () => gitState.stageSelected(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.surfaceLight,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Stage (${gitState.selectedFiles.length})', style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commitController,
                    decoration: InputDecoration(
                      hintText: 'Commit message...',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      filled: true,
                      fillColor: AppTheme.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: gitState.isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Commit & Push to Remote'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: gitState.isLoading
                          ? null
                          : () {
                              final msg = _commitController.text;
                              if (msg.trim().isNotEmpty) {
                                gitState.commitAndPush(msg, stageAll: true, push: true);
                                _commitController.clear();
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'modified':
        return Colors.amberAccent;
      case 'new':
      case 'untracked':
        return Colors.greenAccent;
      case 'deleted':
        return Colors.redAccent;
      default:
        return AppTheme.textSecondary;
    }
  }
}
