import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum VoiceRecorderPhase { idle, recording, locked }

class VoiceNoteRecorder {
  VoiceNoteRecorder({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  Timer? _timer;
  void Function(Duration elapsed)? onTick;

  VoiceRecorderPhase phase = VoiceRecorderPhase.idle;
  Duration elapsed = Duration.zero;
  String? _path;

  Future<bool> start() async {
    if (phase != VoiceRecorderPhase.idle) return false;
    if (!await _recorder.hasPermission()) return false;

    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
      ),
      path: _path!,
    );
    phase = VoiceRecorderPhase.recording;
    elapsed = Duration.zero;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed += const Duration(seconds: 1);
      onTick?.call(elapsed);
    });
    return true;
  }

  void lock() {
    if (phase == VoiceRecorderPhase.recording) {
      phase = VoiceRecorderPhase.locked;
    }
  }

  Future<File?> finish() async {
    if (phase == VoiceRecorderPhase.idle) return null;
    _timer?.cancel();
    _timer = null;
    final path = await _recorder.stop();
    phase = VoiceRecorderPhase.idle;
    final resolved = path ?? _path;
    _path = null;
    if (resolved == null) return null;
    final file = File(resolved);
    if (!await file.exists() || await file.length() < 800) {
      await _safeDelete(file);
      return null;
    }
    return file;
  }

  Future<void> cancel() async {
    if (phase == VoiceRecorderPhase.idle) return;
    _timer?.cancel();
    _timer = null;
    final path = await _recorder.stop();
    phase = VoiceRecorderPhase.idle;
    final resolved = path ?? _path;
    _path = null;
    if (resolved != null) {
      await _safeDelete(File(resolved));
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    if (phase != VoiceRecorderPhase.idle) {
      await _recorder.stop();
    }
    await _recorder.dispose();
    phase = VoiceRecorderPhase.idle;
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
