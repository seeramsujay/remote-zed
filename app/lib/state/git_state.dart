import 'package:flutter/foundation.dart';
import '../models/git_models.dart';
import '../services/git_service.dart';

/// State management for Git repository operations, file staging, diff inspection, and commits.
class GitState extends ChangeNotifier {
  final GitService gitService;

  GitStatusResult? _status;
  final Set<String> _selectedFiles = {};
  GitDiffResult? _selectedDiff;
  bool _isLoading = false;
  String? _statusMessage;

  GitState({required this.gitService});

  GitStatusResult? get status => _status;
  Set<String> get selectedFiles => _selectedFiles;
  GitDiffResult? get selectedDiff => _selectedDiff;
  bool get isLoading => _isLoading;
  String? get statusMessage => _statusMessage;

  /// Refreshes repository status.
  Future<void> refreshStatus() async {
    _isLoading = true;
    _statusMessage = null;
    notifyListeners();

    try {
      _status = await gitService.getStatus();
    } catch (e) {
      _statusMessage = 'Git error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggles selection of a file for staging.
  void toggleFileSelection(String path) {
    if (_selectedFiles.contains(path)) {
      _selectedFiles.remove(path);
    } else {
      _selectedFiles.add(path);
    }
    notifyListeners();
  }

  /// Selects or deselects all modified files.
  void toggleSelectAll() {
    if (_status == null) return;
    if (_selectedFiles.length == _status!.files.length) {
      _selectedFiles.clear();
    } else {
      _selectedFiles.addAll(_status!.files.map((f) => f.path));
    }
    notifyListeners();
  }

  /// Fetches diff for a specific file or all files.
  Future<void> loadDiff(String? path) async {
    _isLoading = true;
    notifyListeners();

    try {
      _selectedDiff = await gitService.getDiff(path: path);
    } catch (e) {
      _statusMessage = 'Failed to load diff: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Stages currently selected files.
  Future<void> stageSelected() async {
    if (_selectedFiles.isEmpty) return;
    _isLoading = true;
    notifyListeners();

    try {
      await gitService.stageFiles(_selectedFiles.toList());
      _selectedFiles.clear();
      await refreshStatus();
    } catch (e) {
      _statusMessage = 'Failed to stage files: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Commits with given message and optionally pushes immediately.
  Future<void> commitAndPush(String message, {bool stageAll = false, bool push = true}) async {
    if (message.trim().isEmpty) return;
    _isLoading = true;
    notifyListeners();

    try {
      await gitService.commit(message.trim(), stageAll: stageAll);
      if (push) {
        await gitService.push();
      }
      _statusMessage = 'Commit & push completed';
      await refreshStatus();
    } catch (e) {
      _statusMessage = 'Commit failed: $e';
      _isLoading = false;
      notifyListeners();
    }
  }
}
