import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mobile/features/chat/widgets/voice_note_recorder.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.llfbandit.record/messages');
  late Directory tempDir;
  late bool permission;
  late int fileBytesOnStop;
  late String? startedPath;
  late String? lastStartedPath;
  late int stopCount;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('voice_recorder_test');
    permission = true;
    fileBytesOnStop = 1000;
    startedPath = null;
    lastStartedPath = null;
    stopCount = 0;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasPermission':
          return permission;
        case 'start':
          final args = call.arguments as Map;
          startedPath = args['path'] as String?;
          lastStartedPath = startedPath;
          return null;
        case 'stop':
          stopCount++;
          final path = startedPath;
          startedPath = null;
          if (path != null) {
            await File(path).writeAsBytes(List<int>.filled(fileBytesOnStop, 1));
          }
          return path;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('VoiceNoteRecorder', () {
    test('client-side duration ceiling matches the backend 10-min rule',
        () {
      expect(VoiceNoteRecorder.maxDuration, const Duration(minutes: 10));
    });

    test('start → recording, finish → file, phase flips to idle', () async {
      final rec = VoiceNoteRecorder();
      expect(await rec.start(), isTrue);
      expect(rec.phase, VoiceRecorderPhase.recording);

      final file = await rec.finish();
      expect(file, isNotNull);
      expect(await file!.exists(), isTrue);
      expect(await file.length(), greaterThanOrEqualTo(800));
      expect(rec.phase, VoiceRecorderPhase.idle);
      await rec.dispose();
    });

    test('second finish is a no-op (sync phase guard prevents double-send)',
        () async {
      final rec = VoiceNoteRecorder();
      await rec.start();
      expect(await rec.finish(), isNotNull);
      expect(await rec.finish(), isNull);
      expect(stopCount, 1); // platform stop called exactly once
      await rec.dispose();
    });

    test('finish racing a prior cancel yields null', () async {
      final rec = VoiceNoteRecorder();
      await rec.start();
      await rec.cancel(); // phase → idle synchronously
      expect(await rec.finish(), isNull);
      expect(rec.phase, VoiceRecorderPhase.idle);
      await rec.dispose();
    });

    test('cancel stops the recorder and deletes the raw file', () async {
      final rec = VoiceNoteRecorder();
      await rec.start();
      await rec.cancel();
      expect(rec.phase, VoiceRecorderPhase.idle);
      expect(lastStartedPath, isNotNull);
      expect(await File(lastStartedPath!).exists(), isFalse);
      await rec.dispose();
    });

    test('too-short recording is discarded, not returned', () async {
      fileBytesOnStop = 100; // < 800-byte minimum
      final rec = VoiceNoteRecorder();
      await rec.start();
      expect(await rec.finish(), isNull);
      expect(await File(lastStartedPath!).exists(), isFalse);
      await rec.dispose();
    });

    test('permission denied leaves the recorder idle', () async {
      permission = false;
      final rec = VoiceNoteRecorder();
      expect(await rec.start(), isFalse);
      expect(rec.phase, VoiceRecorderPhase.idle);
      await rec.dispose();
    });

    test('second start while recording is refused', () async {
      final rec = VoiceNoteRecorder();
      await rec.start();
      expect(await rec.start(), isFalse);
      expect(rec.phase, VoiceRecorderPhase.recording);
      await rec.dispose();
    });

    test('dispose during recording stops and deletes the raw file', () async {
      final rec = VoiceNoteRecorder();
      await rec.start();
      await rec.dispose();
      expect(rec.phase, VoiceRecorderPhase.idle);
      expect(await File(lastStartedPath!).exists(), isFalse);
    });
  });
}
