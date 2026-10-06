/// Data models for Git operations and repository inspection.
library;

class GitFileStatus {
  final String path;
  final String status;
  final bool staged;
  final int insertions;
  final int deletions;

  GitFileStatus({
    required this.path,
    required this.status,
    required this.staged,
    this.insertions = 0,
    this.deletions = 0,
  });

  factory GitFileStatus.fromJson(Map<String, dynamic> json) {
    return GitFileStatus(
      path: json['path'] as String? ?? '',
      status: json['status'] as String? ?? 'modified',
      staged: json['staged'] as bool? ?? false,
      insertions: json['insertions'] as int? ?? 0,
      deletions: json['deletions'] as int? ?? 0,
    );
  }
}

class GitStatusResult {
  final String branch;
  final bool clean;
  final int ahead;
  final int behind;
  final List<GitFileStatus> files;

  GitStatusResult({
    required this.branch,
    required this.clean,
    this.ahead = 0,
    this.behind = 0,
    required this.files,
  });

  factory GitStatusResult.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as List<dynamic>? ?? [];
    return GitStatusResult(
      branch: json['branch'] as String? ?? 'HEAD',
      clean: json['clean'] as bool? ?? true,
      ahead: json['ahead'] as int? ?? 0,
      behind: json['behind'] as int? ?? 0,
      files: rawFiles.map((f) => GitFileStatus.fromJson(f as Map<String, dynamic>)).toList(),
    );
  }
}

class GitDiffResult {
  final String path;
  final String diff;
  final int insertions;
  final int deletions;

  GitDiffResult({
    required this.path,
    required this.diff,
    this.insertions = 0,
    this.deletions = 0,
  });

  factory GitDiffResult.fromJson(Map<String, dynamic> json) {
    return GitDiffResult(
      path: json['path'] as String? ?? '',
      diff: json['diff'] as String? ?? '',
      insertions: json['insertions'] as int? ?? 0,
      deletions: json['deletions'] as int? ?? 0,
    );
  }
}

class GitCommitResult {
  final String commitHash;
  final String branch;
  final String summary;

  GitCommitResult({
    required this.commitHash,
    required this.branch,
    required this.summary,
  });

  factory GitCommitResult.fromJson(Map<String, dynamic> json) {
    return GitCommitResult(
      commitHash: json['commit_hash'] as String? ?? json['commitHash'] as String? ?? '',
      branch: json['branch'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
    );
  }
}
