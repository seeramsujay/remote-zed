import 'package:flutter/foundation.dart';
import '../models/terminal_models.dart';
import '../services/terminal_service.dart';

/// State management for browsing host directories and switching workspace roots.
class FileSystemState extends ChangeNotifier {
  final TerminalService terminalService;

  FsListResult? _currentListing;
  bool _isLoading = false;
  String? _errorMessage;

  FileSystemState({required this.terminalService}) {
    refresh();
  }

  FsListResult? get currentListing => _currentListing;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Loads or refreshes the file listing for `path`.
  Future<void> loadPath([String? path]) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentListing = await terminalService.listDirectory(path);
    } catch (e) {
      _errorMessage = 'Failed to load directory: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refreshes current directory.
  Future<void> refresh() async {
    await loadPath(_currentListing?.currentPath);
  }

  /// Navigates up to parent directory.
  Future<void> navigateUp() async {
    if (_currentListing?.parentPath != null) {
      await loadPath(_currentListing!.parentPath);
    }
  }

  /// Creates a new subfolder in the current directory.
  Future<void> createFolder(String folderName) async {
    final trimmed = folderName.trim();
    if (trimmed.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      await terminalService.createDirectory(trimmed);
      await refresh();
    } catch (e) {
      _errorMessage = 'Failed to create folder: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets the active directory as workspace root for AI Agent and Git.
  Future<void> setAsActiveWorkspace() async {
    if (_currentListing == null) return;
    try {
      await terminalService.setWorkspace(_currentListing!.currentPath);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to set workspace: $e';
      notifyListeners();
    }
  }
}
