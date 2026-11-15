import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'websocket_client.dart';

/// Credentials obtained via scanning the terminal QR code or pasting pairing URI.
class BunkerCredentials {
  final String topic;
  final String key;
  final String token;
  final int localPort;

  BunkerCredentials({
    required this.topic,
    required this.key,
    required this.token,
    this.localPort = 8443,
  });

  /// Backward-compatible getter for keyHex
  String get keyHex => key;

  /// Parses credentials from ZEDBUNKER:<base64-json>, raw JSON, or zed-remote://pair URI.
  static BunkerCredentials? parse(String rawInput) {
    final text = rawInput.trim();
    if (text.isEmpty) return null;

    // 1. ZEDBUNKER:<base64> format (from zed-tunnel terminal QR code)
    if (text.startsWith('ZEDBUNKER:')) {
      final payload = text.substring('ZEDBUNKER:'.length).trim();
      try {
        final decodedBytes = _safeBase64Decode(payload);
        final jsonStr = utf8.decode(decodedBytes);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final topic = (map['ntfy_topic'] ?? map['topic']) as String?;
        final key = (map['key'] ?? map['encryption_key']) as String?;
        final token = (map['token'] ?? '') as String;
        final port = (map['port'] as num?)?.toInt() ?? 8443;

        if (topic != null && key != null) {
          return BunkerCredentials(
            topic: topic,
            key: key,
            token: token,
            localPort: port,
          );
        }
      } catch (e) {
        debugPrint('Failed to parse ZEDBUNKER payload: $e');
      }
    }

    // 2. Raw JSON string format
    if (text.startsWith('{') && text.contains('ntfy_topic')) {
      try {
        final map = jsonDecode(text) as Map<String, dynamic>;
        final topic = (map['ntfy_topic'] ?? map['topic']) as String?;
        final key = (map['key'] ?? map['encryption_key']) as String?;
        final token = (map['token'] ?? '') as String;
        final port = (map['port'] as num?)?.toInt() ?? 8443;

        if (topic != null && key != null) {
          return BunkerCredentials(
            topic: topic,
            key: key,
            token: token,
            localPort: port,
          );
        }
      } catch (e) {
        debugPrint('Failed to parse JSON Bunker payload: $e');
      }
    }

    // 3. zed-remote://pair URI format
    try {
      final uri = Uri.parse(text);
      if (uri.scheme == 'zed-remote' && uri.host == 'pair') {
        final topic = uri.queryParameters['topic'];
        final key = uri.queryParameters['key'];
        final token = uri.queryParameters['token'] ?? '';
        final portStr = uri.queryParameters['port'];

        if (topic != null && key != null) {
          return BunkerCredentials(
            topic: topic,
            key: key,
            token: token,
            localPort: portStr != null ? int.tryParse(portStr) ?? 8443 : 8443,
          );
        }
      }
    } catch (_) {}

    return null;
  }

  /// Alias for backward compatibility
  static BunkerCredentials? fromUri(String uriString) => parse(uriString);

  static List<int> _safeBase64Decode(String input) {
    final normalized = base64.normalize(input);
    try {
      return base64Url.decode(normalized);
    } catch (_) {
      return base64.decode(normalized);
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
    _lastTunnelUrl = null;
  }

  /// Fetches latest ciphertext from ntfy.sh and decrypts it using AES-256-GCM.
  Future<void> fetchAndApplyTunnel() async {
    if (_credentials == null) return;

    try {
      final ntfyUrl = Uri.parse('https://ntfy.sh/${_credentials!.topic}/raw?poll=1');
      final res = await http.get(ntfyUrl).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        final lines = res.body.trim().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
        if (lines.isEmpty) return;
        final latestCiphertext = lines.last;

        final decrypted = await decryptPayload(_credentials!.key, latestCiphertext);
        if (decrypted != null) {
          final host = decrypted['host'] as String?;
          final port = decrypted['port'] as int?;
          final tunnelUrl = decrypted['tunnel_url'] as String?;

          if (host != null && port != null) {
            if (_lastTunnelUrl != tunnelUrl ||
                webSocketClient.host != host ||
                webSocketClient.port != port) {
              debugPrint('Bunker tunnel update: routing to $host:$port ($tunnelUrl)');
              _lastTunnelUrl = tunnelUrl ?? '$host:$port';

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

  /// Decrypts a base64/base64url-encoded AES-256-GCM payload using 256-bit key (Base64 or Hex).
  static Future<Map<String, dynamic>?> decryptPayload(String keyRaw, String b64Ciphertext) async {
    try {
      final keyBytes = _parseKeyBytes(keyRaw);
      if (keyBytes == null || keyBytes.length != 32) {
        debugPrint('Invalid AES-256 key: expected 32 bytes');
        return null;
      }

      final rawBlob = _safeBase64Blob(b64Ciphertext);
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
      final plainText = utf8.decode(clearTextBytes).trim();

      // Check if plaintext is a JSON map
      if (plainText.startsWith('{') && plainText.endsWith('}')) {
        try {
          final parsed = jsonDecode(plainText);
          if (parsed is Map<String, dynamic>) {
            return parsed;
          }
        } catch (_) {}
      }

      // Plaintext is a URL / host:port string (e.g. "tcp://ktupz-...run.pinggy-free.link:43767")
      var cleaned = plainText;
      for (final prefix in ['tcp://', 'ssl://', 'http://', 'https://']) {
        if (cleaned.startsWith(prefix)) {
          cleaned = cleaned.substring(prefix.length);
          break;
        }
      }
      cleaned = cleaned.split('/')[0]; // Remove any trailing path

      final colonIdx = cleaned.lastIndexOf(':');
      if (colonIdx != -1) {
        final host = cleaned.substring(0, colonIdx);
        final port = int.tryParse(cleaned.substring(colonIdx + 1));
        if (host.isNotEmpty && port != null) {
          return {
            'host': host,
            'port': port,
            'tunnel_url': plainText,
          };
        }
      }

      return {'tunnel_url': plainText};
    } catch (e) {
      debugPrint('Failed to decrypt bunker payload: $e');
      return null;
    }
  }

  static List<int>? _parseKeyBytes(String keyStr) {
    final trimmed = keyStr.trim();
    // Try hex if 64 chars hex
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmed)) {
      final bytes = <int>[];
      for (var i = 0; i < trimmed.length; i += 2) {
        bytes.add(int.parse(trimmed.substring(i, i + 2), radix: 16));
      }
      return bytes;
    }

    // Try Base64
    try {
      final decoded = _safeBase64Blob(trimmed);
      if (decoded.length == 32) return decoded;
    } catch (_) {}

    return null;
  }

  static List<int> _safeBase64Blob(String input) {
    final normalized = base64.normalize(input.trim());
    try {
      return base64Url.decode(normalized);
    } catch (_) {
      return base64.decode(normalized);
    }
  }

  void dispose() {
    deactivate();
  }
}
