import 'package:flutter_test/flutter_test.dart';
import 'package:zed_remote_app/models/acp_models.dart';
import 'package:zed_remote_app/models/git_models.dart';
import 'package:zed_remote_app/models/telemetry_models.dart';

void main() {
  group('ACP Models Test', () {
    test('MessageTurn aggregates content and thoughts correctly', () {
      final turn = MessageTurn(
        id: '1',
        role: MessageRole.agent,
        initialContent: 'Initial ',
      );

      turn.appendContent('chunk 1, ');
      turn.appendContent('chunk 2');
      turn.appendThought('Deliberating on file edits...');

      expect(turn.content, equals('Initial chunk 1, chunk 2'));
      expect(turn.thoughts.length, equals(1));
      expect(turn.thoughts.first.text, equals('Deliberating on file edits...'));
    });

    test('PermissionRequest deserializes correctly from JSON-RPC frame', () {
      final jsonFrame = {
        'jsonrpc': '2.0',
        'id': 42,
        'method': 'session/request_permission',
        'params': {
          'sessionId': 'sess_123',
          'toolCall': {
            'toolCallId': 'call_abc',
            'name': 'terminal/create',
            'parameters': {'command': 'cargo check'},
          },
        },
      };

      final req = PermissionRequest.fromJson(jsonFrame);
      expect(req.requestId, equals(42));
      expect(req.sessionId, equals('sess_123'));
      expect(req.toolCallId, equals('call_abc'));
      expect(req.toolName, equals('terminal/create'));
      expect(req.parameters['command'], equals('cargo check'));
    });
  });

  group('Git Models Test', () {
    test('GitStatusResult parses branch and modified files', () {
      final json = {
        'branch': 'feature/acp',
        'clean': false,
        'ahead': 1,
        'behind': 0,
        'files': [
          {
            'path': 'src/main.rs',
            'status': 'modified',
            'staged': true,
            'insertions': 10,
            'deletions': 2,
          },
        ],
      };

      final status = GitStatusResult.fromJson(json);
      expect(status.branch, equals('feature/acp'));
      expect(status.clean, isFalse);
      expect(status.files.length, equals(1));
      expect(status.files.first.path, equals('src/main.rs'));
      expect(status.files.first.staged, isTrue);
    });
  });

  group('Telemetry Models Test', () {
    test('TelemetryResult calculates memory percentage accurately', () {
      final json = {
        'host_name': 'laptop-box',
        'os': 'Linux Mint 22.3',
        'cpu_usage_percent': 24.5,
        'memory_used_bytes': 4000000000,
        'memory_total_bytes': 8000000000,
        'battery_percent': 85.0,
        'is_charging': true,
        'uptime_seconds': 7200,
      };

      final telem = TelemetryResult.fromJson(json);
      expect(telem.hostName, equals('laptop-box'));
      expect(telem.cpuUsagePercent, equals(24.5));
      expect(telem.memoryUsagePercent, closeTo(50.0, 0.1));
      expect(telem.isCharging, isTrue);
      expect(telem.batteryPercent, equals(85.0));
    });
  });
}
