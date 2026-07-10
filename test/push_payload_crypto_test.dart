import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/push/push_payload_crypto.dart';
import 'package:mobile/features/auth/models/auth_models.dart';

void main() {
  const crypto = PushPayloadCrypto();

  test('decrypts AES-256-GCM payload from backend shape', () async {
    final algorithm = AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKey();
    final keyBytes = await secretKey.extractBytes();
    final material = PushCryptoMaterial(
      algorithm: 'AES-256-GCM',
      keyVersion: 1,
      key: base64Encode(keyBytes),
    );

    final plaintext = utf8.encode(
      jsonEncode({
        'type': 'chat_message',
        'roomId': 'room-1',
        'roomName': 'Class Announcement',
        'preview': 'Hello class',
      }),
    );
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: algorithm.newNonce(),
    );

    final payload = await crypto.decrypt(material, {
      'iv': base64Encode(secretBox.nonce),
      'ct': base64Encode(secretBox.cipherText),
      'tag': base64Encode(secretBox.mac.bytes),
      'v': '1',
      'alg': 'AES-256-GCM',
    });

    expect(payload, isNotNull);
    expect(payload!['type'], 'chat_message');
    expect(payload['roomId'], 'room-1');
    expect(payload['roomName'], 'Class Announcement');
    expect(payload['preview'], 'Hello class');
  });

  test('returns null for wrong algorithm or missing fields', () async {
    final material = PushCryptoMaterial(
      algorithm: 'AES-CBC',
      keyVersion: 1,
      key: base64Encode(List.filled(32, 1)),
    );
    expect(await crypto.decrypt(material, {'iv': 'a', 'ct': 'b', 'tag': 'c'}), isNull);
    expect(
      await crypto.decrypt(
        PushCryptoMaterial(algorithm: 'AES-256-GCM', keyVersion: 1, key: ''),
        {'iv': 'a', 'ct': 'b', 'tag': 'c'},
      ),
      isNull,
    );
  });
}
