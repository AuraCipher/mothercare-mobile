import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/chat/data/chat_attachment_queue.dart';
import 'package:mobile/features/chat/models/chat_models.dart';
import 'package:mobile/features/chat/utils/voice_mime.dart';
import 'package:mobile/features/uploads/upload_task.dart';

/// Builds a minimal ISO-BMFF header: size(4) + 'ftyp' + brand(4).
Uint8List ftypBytes(String brand, {bool withFtyp = true}) {
  final bytes = <int>[0, 0, 0, 24];
  if (withFtyp) {
    bytes.addAll('ftyp'.codeUnits);
    bytes.addAll(brand.codeUnits);
  } else {
    bytes.addAll('free'.codeUnits);
    bytes.addAll([0, 0, 0, 0]);
  }
  return Uint8List.fromList(bytes);
}

Future<File> writeTemp(Directory dir, List<int> bytes, String name) async {
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

UploadTask task({
  required String purpose,
  String mimeType = 'application/octet-stream',
  String? scopeJson,
}) {
  return UploadTask(
    taskId: 't1',
    userId: 'u1',
    idempotencyKey: 'k1',
    localPath: '/tmp/x',
    fileName: 'x',
    mimeType: mimeType,
    purpose: purpose,
    expectedSize: 1,
    scopeJson: scopeJson,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('voice_mime_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('voiceDeclaredMimeType (ftyp brand → declared MIME)', () {
    test('Android-style mp42 brand declares video/mp4 (sniffer emits video/mp4)',
        () async {
      final f = await writeTemp(tempDir, ftypBytes('mp42'), 'a.m4a');
      expect(await voiceDeclaredMimeType(f), 'video/mp4');
    });

    test("iOS-style 'M4A ' brand declares audio/x-m4a", () async {
      final f = await writeTemp(tempDir, ftypBytes('M4A '), 'b.m4a');
      expect(await voiceDeclaredMimeType(f), 'audio/x-m4a');
    });

    test('M4B brand declares audio/mp4', () async {
      final f = await writeTemp(tempDir, ftypBytes('M4B '), 'c.m4a');
      expect(await voiceDeclaredMimeType(f), 'audio/mp4');
    });

    test('3gpp brand lands on audio/x-m4a (server ext fallback path)', () async {
      final f = await writeTemp(tempDir, ftypBytes('3g2a'), 'd.m4a');
      expect(await voiceDeclaredMimeType(f), 'audio/x-m4a');
    });

    test('unknown brand defaults to video/mp4 (file-type default)', () async {
      final f = await writeTemp(tempDir, ftypBytes('isom'), 'e.m4a');
      expect(await voiceDeclaredMimeType(f), 'video/mp4');
    });

    test('missing ftyp falls back to audio/x-m4a (ext-map fallback)', () async {
      final f = await writeTemp(tempDir, ftypBytes('', withFtyp: false), 'f.m4a');
      expect(await voiceDeclaredMimeType(f), 'audio/x-m4a');
    });

    test('unreadable file falls back to audio/x-m4a', () async {
      expect(await voiceDeclaredMimeType(File('${tempDir.path}/missing.m4a')),
          'audio/x-m4a');
    });

    test('real device recordings (if present) declare video/mp4', () async {
      final real = Directory('/home/hasan/MCS-App/backend/dist/uploads/chat');
      if (!real.existsSync()) return; // environment without artifacts
      final files = real
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.m4a'))
          .toList();
      if (files.isEmpty) return;
      for (final f in files) {
        expect(await voiceDeclaredMimeType(f), 'video/mp4',
            reason: 'device files sniff as video/mp4 (ftyp mp42)');
      }
    });
  });

  group('isVoiceUploadTask (identity across the purpose switch)', () {
    test('legacy purpose voice_note is voice', () {
      expect(isVoiceUploadTask(task(purpose: 'voice_note')), isTrue);
    });

    test('purpose chat with scope kind voice is voice', () {
      expect(
        isVoiceUploadTask(
          task(purpose: 'chat', scopeJson: '{"kind":"voice","roomId":"r1"}'),
        ),
        isTrue,
      );
    });

    test('purpose chat with image kind is NOT voice', () {
      expect(
        isVoiceUploadTask(
          task(purpose: 'chat', scopeJson: '{"kind":"image"}'),
        ),
        isFalse,
      );
    });

    test('purpose video is NOT voice', () {
      expect(isVoiceUploadTask(task(purpose: 'video')), isFalse);
    });
  });

  group('ChatMessageMedia voice/video markers', () {
    test('purpose chat + video/mp4 (Android voice) is voice, not video', () {
      const m = ChatMessageMedia(
        id: 'f1',
        mimeType: 'video/mp4',
        url: '/api/uploads/f1',
        purpose: 'chat',
      );
      expect(m.isVoiceNote, isTrue);
      expect(m.isAudio, isTrue);
      expect(m.isVideo, isFalse);
    });

    test('purpose chat + audio/x-m4a (iOS voice) is voice', () {
      const m = ChatMessageMedia(
        id: 'f2',
        mimeType: 'audio/x-m4a',
        url: '/api/uploads/f2',
        purpose: 'chat',
      );
      expect(m.isVoiceNote, isTrue);
      expect(m.isVideo, isFalse);
    });

    test('legacy voice_note stays voice', () {
      const m = ChatMessageMedia(
        id: 'f3',
        mimeType: 'audio/mp4',
        url: '/api/uploads/f3',
        purpose: 'voice_note',
      );
      expect(m.isVoiceNote, isTrue);
      expect(m.isVideo, isFalse);
    });

    test('real chat video (purpose video) stays video', () {
      const m = ChatMessageMedia(
        id: 'f4',
        mimeType: 'video/mp4',
        url: '/api/uploads/f4',
        purpose: 'video',
      );
      expect(m.isVoiceNote, isFalse);
      expect(m.isVideo, isTrue);
    });

    test('image is image, never voice', () {
      const m = ChatMessageMedia(
        id: 'f5',
        mimeType: 'image/jpeg',
        url: '/api/uploads/f5',
        purpose: 'chat',
      );
      expect(m.isVoiceNote, isFalse);
      expect(m.isImage, isTrue);
      expect(m.isVideo, isFalse);
    });
  });
}
