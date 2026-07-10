import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/models/pending_outgoing_message.dart';

void main() {
  test('PendingOutgoingMessage defaults to uploading phase', () {
    const pending = PendingOutgoingMessage(
      localId: 'local-1',
      type: 'image',
      previewLabel: 'Photo',
    );

    expect(pending.phase, PendingSendPhase.uploading);
    expect(pending.progress, 0);
  });

  test('copyWith updates progress and phase', () {
    const pending = PendingOutgoingMessage(
      localId: 'local-1',
      type: 'video',
      previewLabel: 'Video',
    );

    final sending = pending.copyWith(progress: 1, phase: PendingSendPhase.sending);
    expect(sending.progress, 1);
    expect(sending.phase, PendingSendPhase.sending);
    expect(sending.localId, pending.localId);
    expect(sending.type, pending.type);

    final failed = sending.copyWith(phase: PendingSendPhase.failed);
    expect(failed.phase, PendingSendPhase.failed);
    expect(failed.progress, 1);
  });
}
