import '../models/terminal_models.dart';
import 'websocket_client.dart';

/// Service managing remote interactive shell execution and filesystem browsing.
class TerminalService {
  final WebSocketClient client;

  TerminalService({required this.client});

  /// Executes an arbitrary shell command within the current remote directory.
  Future<TerminalExecResult> exec(String command) async {
    final res = await client.sendRequest('terminal/exec', {
      'command': command,
    });
    return TerminalExecResult.fromJson(res as Map<String, dynamic>);
  }

  /// Queries the active working directory of the terminal supervisor.
  Future<String> getCwd() async {
    final res = await client.sendRequest('terminal/cwd');
    if (res is Map<String, dynamic>) {
      return res['cwd'] as String? ?? '';
    }
    return '';
  }

  /// Lists entries in a directory.
  Future<FsListResult> listDirectory([String? path]) async {
    final res = await client.sendRequest('fs/list', {
      'path': ?path,
    });
    return FsListResult.fromJson(res as Map<String, dynamic>);
  }

  /// Creates a new directory on the host machine.
  Future<String> createDirectory(String path) async {
    final res = await client.sendRequest('fs/mkdir', {
      'path': path,
    });
    if (res is Map<String, dynamic>) {
      return res['path'] as String? ?? path;
    }
    return path;
  }

  /// Updates the host active workspace directory for the agent and git.
  Future<String> setWorkspace(String path) async {
    final res = await client.sendRequest('workspace/set', {
      'path': path,
    });
    if (res is Map<String, dynamic>) {
      return res['workspace'] as String? ?? path;
    }
    return path;
  }
}
