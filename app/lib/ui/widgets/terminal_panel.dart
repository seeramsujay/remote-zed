import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../state/terminal_state.dart';

/// Interactive Termux-style mobile terminal for executing host shell commands over the secure tunnel.
class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final TextEditingController _cmdController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  void _submit(TerminalState state) {
    final cmd = _cmdController.text;
    if (cmd.trim().isEmpty) return;
    state.runCommand(cmd);
    _cmdController.clear();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _insertKey(String key) {
    final text = _cmdController.text;
    final selection = _cmdController.selection;
    final newText = text.replaceRange(
      selection.start >= 0 ? selection.start : text.length,
      selection.end >= 0 ? selection.end : text.length,
      key,
    );
    _cmdController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: (selection.start >= 0 ? selection.start : text.length) + key.length,
      ),
    );
  }

  @override
  void dispose() {
    _cmdController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final termState = context.watch<TerminalState>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (termState.isRunning) {
        _scrollToBottom();
      }
    });

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          // Header status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 16, color: AppTheme.primaryAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    termState.cwd,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (termState.isRunning)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryAccent),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  tooltip: 'Clear screen',
                  onPressed: termState.clear,
                ),
              ],
            ),
          ),

          // Output screen
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: termState.lines.length,
              itemBuilder: (context, index) {
                final line = termState.lines[index];

                if (line.isInput) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 2.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '\$ ',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line.text,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return SelectableText(
                  line.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: line.isError ? Colors.redAccent : const Color(0xFFD4D4D8),
                    height: 1.35,
                  ),
                );
              },
            ),
          ),

          // Mobile Terminal Quick Keys Bar (Termux-style)
          Container(
            height: 38,
            color: const Color(0xFF18181B),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: [
                _buildQuickKey('TAB', () => _insertKey('\t')),
                _buildQuickKey('~', () => _insertKey('~')),
                _buildQuickKey('/', () => _insertKey('/')),
                _buildQuickKey('-', () => _insertKey('-')),
                _buildQuickKey('|', () => _insertKey('|')),
                _buildQuickKey('..', () => _insertKey('..')),
                _buildQuickKey('↑', () {
                  final prev = termState.historyUp();
                  if (prev != null) _cmdController.text = prev;
                }),
                _buildQuickKey('↓', () {
                  final next = termState.historyDown();
                  if (next != null) _cmdController.text = next;
                }),
                _buildQuickKey('Ctrl-C', () => termState.runCommand('^C')),
                _buildQuickKey('CLEAR', termState.clear),
              ],
            ),
          ),

          // Command input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: const Color(0xFF27272A),
            child: Row(
              children: [
                const Text(
                  '\$ ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _cmdController,
                    focusNode: _focusNode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'type command (e.g. ls -la, mkdir myapp, cargo new)...',
                      hintStyle: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white38,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _submit(termState),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18, color: Colors.greenAccent),
                  onPressed: () => _submit(termState),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickKey(String label, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Material(
        color: const Color(0xFF27272A),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
