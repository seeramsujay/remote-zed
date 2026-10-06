/// Data models for the interactive mobile terminal and remote file system browser.
library;

class TerminalExecResult {
  final String stdout;
  final String stderr;
  final int exitCode;
  final String cwd;

  TerminalExecResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.cwd,
  });

  factory TerminalExecResult.fromJson(Map<String, dynamic> json) {
    return TerminalExecResult(
      stdout: json['stdout'] as String? ?? '',
      stderr: json['stderr'] as String? ?? '',
      exitCode: json['exit_code'] as int? ?? json['exitCode'] as int? ?? 0,
      cwd: json['cwd'] as String? ?? '',
    );
  }
}

class FileEntry {
  final String name;
  final String path;
  final bool isDir;
  final int sizeBytes;
  final int modifiedEpochSecs;

  FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.sizeBytes,
    required this.modifiedEpochSecs,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      isDir: json['is_dir'] as bool? ?? json['isDir'] as bool? ?? false,
      sizeBytes: json['size_bytes'] as int? ?? json['sizeBytes'] as int? ?? 0,
      modifiedEpochSecs: json['modified_epoch_secs'] as int? ?? json['modifiedEpochSecs'] as int? ?? 0,
    );
  }

  String get humanSize {
    if (isDir) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class FsListResult {
  final String currentPath;
  final String? parentPath;
  final List<FileEntry> entries;

  FsListResult({
    required this.currentPath,
    this.parentPath,
    required this.entries,
  });

  factory FsListResult.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as List<dynamic>? ?? [];
    return FsListResult(
      currentPath: json['current_path'] as String? ?? json['currentPath'] as String? ?? '',
      parentPath: json['parent_path'] as String? ?? json['parentPath'] as String?,
      entries: rawEntries.map((e) => FileEntry.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
