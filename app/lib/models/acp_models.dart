/// Data models for ACP (Agent Client Protocol) conversation turns, thoughts, and permissions.
library;

class ThoughtChunk {
  final String text;
  final DateTime timestamp;

  ThoughtChunk({
    required this.text,
    required this.timestamp,
  });
}

class ToolCallInfo {
  final String toolCallId;
  final String name;
  final Map<String, dynamic> parameters;
  String? result;
  bool isCompleted;

  ToolCallInfo({
    required this.toolCallId,
    required this.name,
    required this.parameters,
    this.result,
    this.isCompleted = false,
  });
}

enum MessageRole { user, agent }

class MessageTurn {
  final String id;
  final MessageRole role;
  StringBuffer contentBuffer;
  final List<ThoughtChunk> thoughts;
  final List<ToolCallInfo> toolCalls;
  bool isStreaming;
  final DateTime timestamp;

  MessageTurn({
    required this.id,
    required this.role,
    String initialContent = '',
    List<ThoughtChunk>? thoughts,
    List<ToolCallInfo>? toolCalls,
    this.isStreaming = false,
    DateTime? timestamp,
  })  : contentBuffer = StringBuffer(initialContent),
        thoughts = thoughts ?? [],
        toolCalls = toolCalls ?? [],
        timestamp = timestamp ?? DateTime.now();

  String get content => contentBuffer.toString();

  void appendContent(String chunk) {
    contentBuffer.write(chunk);
  }

  void appendThought(String thought) {
    thoughts.add(ThoughtChunk(text: thought, timestamp: DateTime.now()));
  }
}

class PermissionRequest {
  final dynamic requestId;
  final String sessionId;
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> parameters;
  final DateTime requestedAt;

  PermissionRequest({
    required this.requestId,
    required this.sessionId,
    required this.toolCallId,
    required this.toolName,
    required this.parameters,
    DateTime? requestedAt,
  }) : requestedAt = requestedAt ?? DateTime.now();

  factory PermissionRequest.fromJson(Map<String, dynamic> json) {
    final params = json['params'] as Map<String, dynamic>? ?? {};
    final toolCall = params['toolCall'] as Map<String, dynamic>? ?? {};
    return PermissionRequest(
      requestId: json['id'],
      sessionId: params['sessionId'] as String? ?? 'default',
      toolCallId: toolCall['toolCallId'] as String? ?? '',
      toolName: toolCall['name'] as String? ?? '',
      parameters: toolCall['parameters'] as Map<String, dynamic>? ?? {},
    );
  }
}
