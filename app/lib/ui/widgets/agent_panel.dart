import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../models/acp_models.dart';
import '../../state/agent_state.dart';
import 'thought_card.dart';

/// Primary panel displaying real-time AI conversation turns, thoughts, and input bar.
class AgentPanel extends StatefulWidget {
  const AgentPanel({super.key});

  @override
  State<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends State<AgentPanel> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleSubmit(AgentState state) {
    final text = _promptController.text;
    if (text.trim().isEmpty) return;
    state.sendPrompt(text);
    _promptController.clear();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agentState = context.watch<AgentState>();
    final turns = agentState.turns;

    // Trigger auto scroll on new token
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (agentState.isStreaming) {
        _scrollToBottom();
      }
    });

    return Column(
      children: [
        // Message thread
        Expanded(
          child: turns.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.terminal, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      const Text(
                        'Zed Remote Agent Session Active',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter a prompt to instruct the host AI agent.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: turns.length,
                  itemBuilder: (context, index) {
                    final turn = turns[index];
                    return _buildMessageTurn(turn);
                  },
                ),
        ),

        // Error banner if any
        if (agentState.errorMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppTheme.danger.withValues(alpha: 0.15),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 16, color: AppTheme.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    agentState.errorMessage!,
                    style: const TextStyle(fontSize: 12, color: AppTheme.danger),
                  ),
                ),
              ],
            ),
          ),

        // Input bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: TextField(
                    controller: _promptController,
                    maxLines: 4,
                    minLines: 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Message AntiGravity...',
                      hintStyle: TextStyle(color: AppTheme.textSecondary),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _handleSubmit(agentState),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: agentState.isStreaming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.arrow_upward, size: 20),
                onPressed: agentState.isStreaming ? null : () => _handleSubmit(agentState),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageTurn(MessageTurn turn) {
    final isUser = turn.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Role header
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUser ? Icons.person : Icons.auto_awesome,
                size: 14,
                color: isUser ? AppTheme.primaryAccent : Colors.purpleAccent,
              ),
              const SizedBox(width: 6),
              Text(
                isUser ? 'You' : 'AntiGravity',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (turn.isStreaming) ...[
                const SizedBox(width: 6),
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primaryAccent),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Thought card if any
          if (turn.thoughts.isNotEmpty) ThoughtCard(thoughts: turn.thoughts),

          // Content body
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isUser ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.border,
              ),
            ),
            child: turn.content.isEmpty && turn.isStreaming
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryAccent),
                      ),
                      SizedBox(width: 8),
                      Text('Thinking...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  )
                : MarkdownBody(
                    data: turn.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(AppTheme.darkTheme).copyWith(
                      p: const TextStyle(fontSize: 14, height: 1.45, color: AppTheme.textPrimary),
                      code: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        backgroundColor: Color(0x33000000),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
