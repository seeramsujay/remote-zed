import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

/// Resilient JSON-RPC WebSocket client with automatic reconnection and request tracking.
class WebSocketClient {
  String host;
  int port;
  String token;
  bool useTls;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  int _nextRequestId = 1;
  final Map<dynamic, Completer<dynamic>> _pendingRequests = {};
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;

  WebSocketClient({
    required this.host,
    required this.port,
    required this.token,
    this.useTls = false,
  });

  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  void updateConfig({required String host, required int port, required String token, bool? useTls}) {
    this.host = host;
    this.port = port;
    this.token = token;
    if (useTls != null) this.useTls = useTls;
    disconnect();
    connect();
  }

  void connect() {
    if (_status == ConnectionStatus.connecting || _status == ConnectionStatus.connected) {
      return;
    }

    _setStatus(ConnectionStatus.connecting);
    _reconnectTimer?.cancel();

    try {
      final scheme = useTls ? 'wss' : 'ws';
      final uri = Uri.parse('$scheme://$host:$port?token=$token');
      debugPrint('Connecting to Zed Remote daemon at $uri');

      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        (data) {
          if (_status != ConnectionStatus.connected) {
            _setStatus(ConnectionStatus.connected);
          }
          _handleRawMessage(data);
        },
        onError: (err) {
          debugPrint('WebSocket error: $err');
          _setStatus(ConnectionStatus.error);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          _setStatus(ConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Connection exception: $e');
      _setStatus(ConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_status != ConnectionStatus.connected) {
        debugPrint('Attempting auto-reconnect...');
        connect();
      }
    });
  }

  void _handleRawMessage(dynamic data) {
    try {
      final text = data is String ? data : utf8.decode(data as List<int>);
      final map = jsonDecode(text) as Map<String, dynamic>;

      // Check if this fulfills a pending JSON-RPC request
      if (map.containsKey('id') && _pendingRequests.containsKey(map['id'])) {
        final completer = _pendingRequests.remove(map['id']);
        if (map.containsKey('error') && map['error'] != null) {
          completer?.completeError(map['error']);
        } else {
          completer?.complete(map['result']);
        }
      }

      // Forward to global stream
      _messageController.add(map);
    } catch (e) {
      debugPrint('Error parsing incoming message frame: $e');
    }
  }

  /// Sends a JSON-RPC 2.0 request and returns a future completing with the result.
  Future<dynamic> sendRequest(String method, [Map<String, dynamic>? params]) {
    final id = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    final frame = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params ?? {},
    };

    final jsonStr = jsonEncode(frame);
    if (_channel != null && _status == ConnectionStatus.connected) {
      _channel!.sink.add(jsonStr);
    } else {
      completer.completeError('WebSocket is not connected');
      _pendingRequests.remove(id);
    }

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request $method ($id) timed out');
      },
    );
  }

  /// Sends a raw JSON-RPC response back to the daemon (used for permission decisions).
  void sendResponse(dynamic id, Map<String, dynamic> result) {
    final frame = {
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    };
    if (_channel != null && _status == ConnectionStatus.connected) {
      _channel!.sink.add(jsonEncode(frame));
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
  }
}
