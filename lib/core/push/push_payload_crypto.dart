import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../features/auth/models/auth_models.dart';

class PushPayloadCrypto {
  const PushPayloadCrypto();

  Future<Map<String, dynamic>?> decrypt(
    PushCryptoMaterial material,
    Map<String, String> data,
  ) async {
    if (material.algorithm != 'AES-256-GCM') return null;
    final ivB64 = data['iv'];
    final ctB64 = data['ct'];
    final tagB64 = data['tag'];
    if (ivB64 == null || ctB64 == null || tagB64 == null) return null;
    if (material.key.isEmpty) return null;

    try {
      final algorithm = AesGcm.with256bits();
      final secretKey = SecretKey(base64Decode(material.key));
      final secretBox = SecretBox(
        base64Decode(ctB64),
        nonce: base64Decode(ivB64),
        mac: Mac(base64Decode(tagB64)),
      );
      final clearBytes = await algorithm.decrypt(secretBox, secretKey: secretKey);
      final decoded = jsonDecode(utf8.decode(clearBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }
}
