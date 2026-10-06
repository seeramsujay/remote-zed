import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zed_remote_app/services/bunker_tunnel_service.dart';

void main() {
  group('Bunker Tunnel Credentials & Crypto Tests', () {
    test('Parses pairing URI successfully', () {
      const uriStr = 'zed-remote://pair?topic=zed-bunker-1234abcd&key=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef&token=tok_secret_99&port=8443';
      final creds = BunkerCredentials.fromUri(uriStr);

      expect(creds, isNotNull);
      expect(creds!.topic, equals('zed-bunker-1234abcd'));
      expect(creds.keyHex.length, equals(64));
      expect(creds.token, equals('tok_secret_99'));
      expect(creds.localPort, equals(8443));
    });

    test('Rejects invalid URI schemes', () {
      expect(BunkerCredentials.fromUri('https://example.com'), isNull);
      expect(BunkerCredentials.fromUri('zed-remote://wrong'), isNull);
    });

    test('Decrypts AES-256-GCM ciphertext payload correctly', () async {
      // Known 256-bit key (32 bytes = 64 hex chars)
      const keyHex = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
      final keyBytes = List<int>.generate(32, (i) => i);
      const testJson = '{"host":"tunnel.free.pinggy.link","port":43210,"tunnel_url":"tcp://tunnel.free.pinggy.link:43210"}';

      // Encrypt with cryptography package
      final algorithm = AesGcm.with256bits();
      final secretKey = SecretKey(keyBytes);
      final secretBox = await algorithm.encrypt(
        utf8.encode(testJson),
        secretKey: secretKey,
      );

      // Pack nonce (12 bytes) + ciphertext + mac (16 bytes)
      final packed = <int>[
        ...secretBox.nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ];
      final b64Blob = base64Url.encode(packed);

      // Decrypt using BunkerTunnelService
      final decrypted = await BunkerTunnelService.decryptPayload(keyHex, b64Blob);

      expect(decrypted, isNotNull);
      expect(decrypted!['host'], equals('tunnel.free.pinggy.link'));
      expect(decrypted['port'], equals(43210));
      expect(decrypted['tunnel_url'], equals('tcp://tunnel.free.pinggy.link:43210'));
    });
  });
}
