import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/acp_models.dart';
import '../services/agent_service.dart';

/// State provider for ACP conversations, reasoning thoughts, and permission requests.
class AgentState extends ChangeNotifier {
  final AgentService agentService;

  final List<MessageTurn> _turns = [];
  PermissionRequest? _pendingPermission;
  bool _isStreaming = false;
  String? _errorMessage;

  StreamSubscription? _updateSub;
  StreamSubscription? _permSub;

  AgentState({required this.agentService}) {
    _initSubscriptions();
  }

  List<MessageTurn> get turns => List.unmodifiable(_turns);
  PermissionRequest? get pendingPermission => _pendingPermission;
  bool get isStreaming => _isStreaming;
  String? get errorMessage => _errorMessage;

  void _initSubscriptions() {
    _updateSub = agentService.updateStream.listen(_handleSessionUpdate);
    _permSub = agentService.permissionStream.listen((perm) {
      _pendingPermission = perm;
      notifyListeners();
    });
  }

  void _handleSessionUpdate(Map<String, dynamic> msg) {
    final params = msg['params'] as Map<String, dynamic>?;
    if (params == null) return;

    final update = params['update'] as Map<String, dynamic>?;
    if (update == null) return;

    final updateType = update['sessionUpdateType'] as String?;

    if (_turns.isEmpty || _turns.last.role != MessageRole.agent || !_turns.last.isStreaming) {
      _turns.add(MessageTurn(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.agent,
        isStreaming: true,
      ));
    }

    final currentTurn = _turns.last;

    switch (updateType) {
      case 'agent_message_chunk':
        final content = update['content'] as Map<String, dynamic>?;
        final text = content?['text'] as String? ?? '';
        currentTurn.appendContent(text);
        _isStreaming = true;
        break;

      case 'agent_thought_chunk':
        final content = update['content'] as Map<String, dynamic>?;
        final text = content?['text'] as String? ?? '';
        currentTurn.appendThought(text);
        break;

      case 'tool_call_started':
        final tc = update['toolCall'] as Map<String, dynamic>?;
        if (tc != null) {
          currentTurn.toolCalls.add(ToolCallInfo(
            toolCallId: tc['toolCallId'] as String? ?? '',
            name: tc['name'] as String? ?? '',
            parameters: tc['parameters'] as Map<String, dynamic>? ?? {},
          ));
        }
        break;

      case 'tool_call_completed':
        final callId = update['tool_call_id'] as String?;
        final res = update['result']?.toString();
        for (var tc in currentTurn.toolCalls) {
          if (tc.toolCallId == callId) {
            tc.isCompleted = true;
            tc.result = res;
          }
        }
        break;

      case 'turn_completed':
        currentTurn.isStreaming = false;
        _isStreaming = false;
        break;
    }

    notifyListeners();
  }

  /// Sends a user prompt to the agent.
  Future<void> sendPrompt(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _turns.add(MessageTurn(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      initialContent: trimmed,
    ));

    _isStreaming = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await agentService.sendPrompt(trimmed);
    } catch (e) {
      _errorMessage = 'Failed to send prompt: $e';
      _isStreaming = false;
      notifyListeners();
    }
  }

  /// Approves the pending permission request.
  void approvePermission() {
    if (_pendingPermission != null) {
      agentService.respondPermission(_pendingPermission!.requestId, true);
      _pendingPermission = null;
      notifyListeners();
    }
  }

  /// Rejects the pending permission request.
  void rejectPermission([String reason = 'Rejected by user']) {
    if (_pendingPermission != null) {
      agentService.respondPermission(_pendingPermission!.requestId, false, reason);
      _pendingPermission = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    _permSub?.cancel();
    super.dispose();
  }
}
