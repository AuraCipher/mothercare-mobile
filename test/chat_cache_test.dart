import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/cache_constants.dart';
import 'package:mobile/core/storage/cached_envelope.dart';
import 'package:mobile/features/chat/models/pending_outgoing_message.dart';

void main() {
  test('CachedEnvelope expires after ttl', () {
    final wrapped = CachedEnvelope.wrap({'hello': 'world'});
    final envelope = CachedEnvelope.parse(
      '{"cachedAt":"2020-01-01T00:00:00.000Z","data":{"hello":"world"}}',
    );
    expect(envelope, isNotNull);
    expect(envelope!.isExpired(const Duration(minutes: 1)), isTrue);
    expect(envelope.data['hello'], 'world');
    expect(wrapped['data'], isA<Map>());
  });

  test('chat landing cache keys are role scoped', () {
    expect(
      chatLandingCacheKey(scope: ChatLandingScope.student, userId: 'u1'),
      'mcs_chat_landing_student_u1',
    );
    expect(
      chatLandingCacheKey(scope: ChatLandingScope.admin, userId: 'u1', branchId: 'b1'),
      'mcs_chat_landing_admin_u1_b1',
    );
  });

  test('PendingOutgoingMessage round-trips json', () {
    const pending = PendingOutgoingMessage(
      localId: 'local-1',
      type: 'video',
      previewLabel: 'Video',
      localFilePath: '/tmp/v.mp4',
      fileName: 'v.mp4',
      purpose: 'video',
      durationSeconds: '12.0',
      academicYearId: 'ay-1',
      phase: PendingSendPhase.failed,
    );
    final restored = PendingOutgoingMessage.fromJson(pending.toJson());
    expect(restored.localId, pending.localId);
    expect(restored.phase, PendingSendPhase.failed);
    expect(restored.fileName, 'v.mp4');
  });
}
