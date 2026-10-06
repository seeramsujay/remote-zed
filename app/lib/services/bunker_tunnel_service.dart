import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'websocket_client.dart';

/// Credentials obtained via scanning the terminal QR code or pasting pairing URI.
class BunkerCredentials {
  final String topic;
  final String keyHex;
  final String token;
  final int localPort;

  BunkerCredentials({
    required this.topic,
    required this.keyHex,
    required this.token,
    this.localPort = 8443,
  });

  /// Parses a `zed-remote://pair?topic=...&key=...&token=...&port=...` URI.
  static BunkerCredentials? fromUri(String uriString) {
    try {
      final uri = Uri.parse(uriString.trim());
      if (uri.scheme != 'zed-remote' || uri.host != 'pair') {
        return null;
      }
      final topic = uri.queryParameters['topic'];
      final key = uri.queryParameters['key'];
      final token = uri.queryParameters['token'];
      final portStr = uri.queryParameters['port'];

      if (topic == null || key == null || token == null) {
        return null;
      }

      return BunkerCredentials(
        topic: topic,
        keyHex: key,
        token: token,
        localPort: portStr != null ? int.tryParse(portStr) ?? 8443 : 8443,
      );
    } catch (e) {
      debugPrint('Failed to parse Bunker URI: $e');
      return null;
    }
  }
}

/// Service managing zero-knowledge tunnel discovery and auto-rotation recovery over ntfy.
class BunkerTunnelService {
  final WebSocketClient webSocketClient;
  BunkerCredentials? _credentials;
  Timer? _pollTimer;
  bool _isListening = false;
  String? _lastTunnelUrl;

  BunkerTunnelService({required this.webSocketClient});

  BunkerCredentials? get credentials => _credentials;
  bool get isActive => _credentials != null && _isListening;
  String? get lastTunnelUrl => _lastTunnelUrl;

  /// Activates bunker mode with the provided credentials.
  void activate(BunkerCredentials creds) {
    _credentials = creds;
    _isListening = true;
    _pollTimer?.cancel();

    // Query immediate state, then poll every 30 seconds
    fetchAndApplyTunnel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      fetchAndApplyTunnel();
    });
  }

  /// Deactivates bunker mode.
  void deactivate() {
    _pollTimer?.cancel();
    _isListening = false;
    _credentials = null;
  }

  /// Fetches latest ciphertext from ntfy.sh and decrypts it using AES-256-GCM.
  Future<void> fetchAndApplyTunnel() async {
    if (_credentials == null) return;

    try {
      final ntfyUrl = Uri.parse('https://ntfy.sh/${_credentials!.topic}/raw');
      final res = await http.get(ntfyUrl).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        final lines = res.body.trim().split('\n');
        final latestCiphertext = lines.last.trim();

        final decrypted = await decryptPayload(_credentials!.keyHex, latestCiphertext);
        if (decrypted != null) {
          final host = decrypted['host'] as String?;
          final port = decrypted['port'] as int?;
          final tunnelUrl = decrypted['tunnel_url'] as String?;

          if (host != null && port != null) {
            if (_lastTunnelUrl != tunnelUrl ||
                webSocketClient.host != host ||
                webSocketClient.port != port) {
              debugPrint('Bunker tunnel update: routing to $host:$port ($tunnelUrl)');
              _lastTunnelUrl = tunnelUrl;

              webSocketClient.updateConfig(
                host: host,
                port: port,
                token: _credentials!.token,
                useTls: false, // Pinggy raw TCP forwards directly to daemon WS
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error polling bunker rendezvous: $e');
    }
  }

  /// Decrypts a base64url-encoded AES-256-GCM payload using the given 256-bit hex key.
  static Future<Map<String, dynamic>?> decryptPayload(String keyHex, String b64Ciphertext) async {
    try {
      final keyBytes = _hexToBytes(keyHex);
      final rawBlob = base64Url.decode(base64.normalize(b64Ciphertext));

      if (rawBlob.length < 28) { // 12-byte nonce + at least 16-byte tag
        return null;
      }

      final nonce = rawBlob.sublist(0, 12);
      final cipherAndTag = rawBlob.sublist(12);
      final cipherText = cipherAndTag.sublist(0, cipherAndTag.length - 16);
      final macBytes = cipherAndTag.sublist(cipherAndTag.length - 16);

      final algorithm = AesGcm.with256bits();
      final secretKey = SecretKey(keyBytes);
      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final clearTextBytes = await algorithm.decrypt(secretBox, secretKey: secretKey);
      final jsonStr = utf8.decode(clearTextBytes);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Failed to decrypt bunker payload: $e');
      return null;
    }
  }

  static List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  void dispose() {
    deactivate();
  }
}
