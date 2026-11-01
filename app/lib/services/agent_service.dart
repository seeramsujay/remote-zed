import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/acp_models.dart';
import 'websocket_client.dart';

/// Coordinates Agent Client Protocol interactions with the remote host.
class AgentService {
  final WebSocketClient client;
  final String sessionId;

  final _updateController = StreamController<Map<String, dynamic>>.broadcast();
  final _permissionController = StreamController<PermissionRequest>.broadcast();

  AgentService({
    required this.client,
    this.sessionId = 'default',
  }) {
    client.messageStream.listen(_handleIncomingMessage);
  }

  Stream<Map<String, dynamic>> get updateStream => _updateController.stream;
  Stream<PermissionRequest> get permissionStream => _permissionController.stream;

  void _handleIncomingMessage(Map<String, dynamic> msg) {
    final method = msg['method'] as String?;

    if (method == 'session/update') {
      _updateController.add(msg);
    } else if (method == 'session/request_permission') {
      final req = PermissionRequest.fromJson(msg);
      _permissionController.add(req);
    }
  }

  /// Sends a prompt to the AI agent.
  Future<void> sendPrompt(String text) async {
    await client.sendRequest('session/prompt', {
      'sessionId': sessionId,
      'prompt': text,
    });
  }

  /// Responds to a pending permission request.
  void respondPermission(dynamic requestId, bool approved, [String? reason]) {
    client.sendResponse(requestId, {
      'decision': approved ? 'approved' : 'rejected',
      'reason': ?reason,
    });
  }

  /// Requests replay of historical session events.
  Future<List<dynamic>> loadSessionHistory([int fromSequence = 0]) async {
    try {
      final res = await client.sendRequest('session/load', {
        'sessionId': sessionId,
        'fromSequence': fromSequence,
      });
      if (res is Map<String, dynamic> && res.containsKey('events')) {
        return res['events'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      debugPrint('Failed to load session history: $e');
      return [];
    }
  }

  void dispose() {
    _updateController.close();
    _permissionController.close();
  }
}
