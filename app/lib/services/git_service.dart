import '../models/git_models.dart';
import 'websocket_client.dart';

/// Service managing remote Git status, diff inspection, staging, committing, and pushing.
class GitService {
  final WebSocketClient client;

  GitService({required this.client});

  /// Fetches the repository status.
  Future<GitStatusResult> getStatus() async {
    final res = await client.sendRequest('git/status');
    return GitStatusResult.fromJson(res as Map<String, dynamic>);
  }

  /// Fetches a unified diff for a path or the entire working tree.
  Future<GitDiffResult> getDiff({String? path, bool staged = false}) async {
    final res = await client.sendRequest('git/diff', {
      if (path != null) 'path': path,
      'staged': staged,
    });
    return GitDiffResult.fromJson(res as Map<String, dynamic>);
  }

  /// Stages the specified file paths.
  Future<void> stageFiles(List<String> paths) async {
    await client.sendRequest('git/stage', {
      'paths': paths,
    });
  }

  /// Commits changes with the given message.
  Future<GitCommitResult> commit(String message, {bool stageAll = false}) async {
    final res = await client.sendRequest('git/commit', {
      'message': message,
      'stageAll': stageAll,
    });
    return GitCommitResult.fromJson(res as Map<String, dynamic>);
  }

  /// Pushes commits to the remote repository.
  Future<String> push({String? remote, String? branch}) async {
    final res = await client.sendRequest('git/push', {
      if (remote != null) 'remote': remote,
      if (branch != null) 'branch': branch,
    });
    if (res is Map<String, dynamic>) {
      return res['message'] as String? ?? 'Pushed successfully';
    }
    return res.toString();
  }
}
