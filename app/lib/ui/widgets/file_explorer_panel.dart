import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../state/file_system_state.dart';

/// File and directory manager for browsing remote folders, creating projects, and setting active workspaces.
class FileExplorerPanel extends StatefulWidget {
  const FileExplorerPanel({super.key});

  @override
  State<FileExplorerPanel> createState() => _FileExplorerPanelState();
}

class _FileExplorerPanelState extends State<FileExplorerPanel> {
  final TextEditingController _folderNameController = TextEditingController();

  void _showNewFolderDialog(FileSystemState fsState) {
    _folderNameController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Create New Directory', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: _folderNameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name (e.g. my-new-project)',
            filled: true,
            fillColor: AppTheme.background,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = _folderNameController.text.trim();
              if (name.isNotEmpty) {
                fsState.createFolder(name);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fsState = context.watch<FileSystemState>();
    final listing = fsState.currentListing;

    return Column(
      children: [
        // Top breadcrumb and actions bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: AppTheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    tooltip: 'Parent Directory',
                    onPressed: listing?.parentPath != null ? fsState.navigateUp : null,
                  ),
                  Expanded(
                    child: Text(
                      listing?.currentPath ?? 'Loading...',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryAccent,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Refresh',
                    onPressed: fsState.refresh,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                    label: const Text('New Folder', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.surfaceLight,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: () => _showNewFolderDialog(fsState),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_special_outlined, size: 16),
                    label: const Text('Set as Workspace', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryAccent,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: () async {
                      await fsState.setAsActiveWorkspace();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Active workspace updated successfully'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Files listing
        Expanded(
          child: fsState.isLoading && listing == null
              ? const Center(child: CircularProgressIndicator())
              : listing == null || listing.entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          const Text('Empty Directory', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('Tap "New Folder" to create a new project directory', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: listing.entries.length,
                      itemBuilder: (context, index) {
                        final entry = listing.entries[index];

                        return ListTile(
                          dense: true,
                          leading: Icon(
                            entry.isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                            color: entry.isDir ? Colors.amberAccent : AppTheme.textSecondary,
                            size: 20,
                          ),
                          title: Text(
                            entry.name,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: entry.isDir ? FontWeight.bold : FontWeight.normal,
                              color: entry.isDir ? AppTheme.textPrimary : const Color(0xFFD4D4D8),
                            ),
                          ),
                          trailing: entry.isDir
                              ? const Icon(Icons.chevron_right, size: 16, color: AppTheme.textSecondary)
                              : Text(
                                  entry.humanSize,
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                          onTap: entry.isDir ? () => fsState.loadPath(entry.path) : null,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
