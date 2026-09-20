import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/storage/cached_envelope.dart';

/// M14 §20 — cache-failure behavior is fail-safe: corrupt/ancient payloads
/// parse to null/expired (never authoritative), so readers fall back to
/// network instead of showing garbage or another user's data.
void main() {
  group('M14 corrupt/stale cache envelopes', () {
    test('garbage payload parses to null', () {
      expect(CachedEnvelope.parse(''), isNull);
      expect(CachedEnvelope.parse('not-json{{{'), isNull);
      expect(CachedEnvelope.parse('{"cachedAt":"nope","data":{}}'), isNull);
      expect(CachedEnvelope.parse('{"cachedAt":"2020-01-01T00:00:00.000Z","data":null}'), isNull);
      expect(CachedEnvelope.parse('{"cachedAt":"2020-01-01T00:00:00.000Z","data":[1,2]}'), isNull);
    });

    test('ancient envelope is expired under every app TTL', () {
      final envelope = CachedEnvelope.parse(
        '{"cachedAt":"2020-01-01T00:00:00.000Z","data":{"a":1}}',
      )!;
      for (final ttl in [
        const Duration(minutes: 30), // landing
        const Duration(hours: 6), // dashboard
        const Duration(hours: 24), // bootstrap
        const Duration(days: 30), // rooms
      ]) {
        expect(envelope.isExpired(ttl), isTrue);
      }
    });

    test('fresh envelope survives round-trip with data intact', () {
      final wrapped = CachedEnvelope.wrap({'room': 'r1', 'n': 3});
      final parsed = CachedEnvelope.parse(
        '{"cachedAt":"${DateTime.now().toUtc().toIso8601String()}","data":{"room":"r1","n":3}}',
      )!;
      expect(parsed.isExpired(const Duration(minutes: 30)), isFalse);
      expect(parsed.data['room'], 'r1');
      expect(wrapped['data'], isA<Map>());
    });
  });
}
