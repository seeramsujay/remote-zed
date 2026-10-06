import 'package:flutter/foundation.dart';
import '../services/terminal_service.dart';

class TerminalLine {
  final String text;
  final bool isInput;
  final bool isError;
  final String? cwd;

  TerminalLine({
    required this.text,
    this.isInput = false,
    this.isError = false,
    this.cwd,
  });
}

/// State provider for the in-app mobile terminal buffer and command history.
class TerminalState extends ChangeNotifier {
  final TerminalService terminalService;

  final List<TerminalLine> _lines = [];
  final List<String> _history = [];
  int _historyIndex = -1;
  String _cwd = '~';
  bool _isRunning = false;

  TerminalState({required this.terminalService}) {
    _initTerminal();
  }

  List<TerminalLine> get lines => List.unmodifiable(_lines);
  List<String> get history => List.unmodifiable(_history);
  String get cwd => _cwd;
  bool get isRunning => _isRunning;

  Future<void> _initTerminal() async {
    _lines.add(TerminalLine(text: 'Zed Remote Interactive Bunker Terminal'));
    _lines.add(TerminalLine(text: 'Encrypted via AES-256-GCM • Zero-Trust Tunnel Active\n'));
    try {
      final remoteCwd = await terminalService.getCwd();
      if (remoteCwd.isNotEmpty) {
        _cwd = remoteCwd;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Executes a command in the terminal.
  Future<void> runCommand(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;

    _history.add(trimmed);
    _historyIndex = _history.length;

    _lines.add(TerminalLine(
      text: trimmed,
      isInput: true,
      cwd: _cwd,
    ));

    _isRunning = true;
    notifyListeners();

    try {
      final result = await terminalService.exec(trimmed);
      _cwd = result.cwd;

      if (result.stdout.isNotEmpty) {
        _lines.add(TerminalLine(text: result.stdout));
      }
      if (result.stderr.isNotEmpty) {
        _lines.add(TerminalLine(text: result.stderr, isError: true));
      }
      if (result.stdout.isEmpty && result.stderr.isEmpty && result.exitCode == 0) {
        // Silent success (e.g. mkdir or cd)
      }
    } catch (e) {
      _lines.add(TerminalLine(text: 'Error: $e', isError: true));
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Clears the terminal screen.
  void clear() {
    _lines.clear();
    _lines.add(TerminalLine(text: 'Terminal screen cleared.\n'));
    notifyListeners();
  }

  /// Recalls previous command from history (Up arrow).
  String? historyUp() {
    if (_history.isEmpty) return null;
    if (_historyIndex > 0) {
      _historyIndex--;
      return _history[_historyIndex];
    }
    return _history.first;
  }

  /// Recalls next command from history (Down arrow).
  String? historyDown() {
    if (_history.isEmpty) return null;
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      return _history[_historyIndex];
    }
    _historyIndex = _history.length;
    return '';
  }
}
