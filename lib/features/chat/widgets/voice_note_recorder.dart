import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum VoiceRecorderPhase { idle, recording, locked }

class VoiceNoteRecorder {
  VoiceNoteRecorder({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  /// Client-side recording ceiling. The backend rejects voice notes whose
  /// ffprobe duration exceeds 10 minutes, so recording stops at the same
  /// limit instead of producing a file that is certain to fail validation.
  static const Duration maxDuration = Duration(minutes: 10);

  final AudioRecorder _recorder;
  Timer? _timer;
  void Function(Duration elapsed)? onTick;

  VoiceRecorderPhase phase = VoiceRecorderPhase.idle;
  Duration elapsed = Duration.zero;
  String? _path;
  bool _finalizing = false;
  bool _disposed = false;

  Future<bool> start() async {
    if (_disposed || _finalizing || phase != VoiceRecorderPhase.idle) return false;
    if (!await _recorder.hasPermission()) return false;
    // The permission dialog outlives the press that requested it, so state
    // can change while it is open.
    if (_disposed || _finalizing || phase != VoiceRecorderPhase.idle) return false;

    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: _path!,
      );
    } catch (_) {
      _path = null;
      return false;
    }
    if (_disposed) {
      final orphan = _path;
      _path = null;
      try {
        await _recorder.stop();
      } catch (_) {}
      if (orphan != null) await _safeDelete(File(orphan));
      return false;
    }
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

  /// Stops the recording and returns the raw file, or null when it is
  /// missing or too short to be a real voice note. The phase flips to idle
  /// synchronously — before any `await` — so a racing second call observes
  /// idle and becomes a no-op; double-send and cancel-vs-send races are
  /// impossible by construction.
  Future<File?> finish() async {
    if (phase == VoiceRecorderPhase.idle || _finalizing) return null;
    _finalizing = true;
    phase = VoiceRecorderPhase.idle;
    final resolved = await _stopNative();
    _finalizing = false;
    if (resolved == null) return null;
    final file = File(resolved);
    if (!await file.exists() || await file.length() < 800) {
      await _safeDelete(file);
      return null;
    }
    return file;
  }

  /// Stops the recording and deletes the raw file. Never yields a file.
  Future<void> cancel() async {
    if (phase == VoiceRecorderPhase.idle || _finalizing) return;
    _finalizing = true;
    phase = VoiceRecorderPhase.idle;
    final resolved = await _stopNative();
    _finalizing = false;
    if (resolved != null) {
      await _safeDelete(File(resolved));
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    if (phase != VoiceRecorderPhase.idle) {
      phase = VoiceRecorderPhase.idle;
      final resolved = await _stopNative();
      if (resolved != null) await _safeDelete(File(resolved));
    } else {
      _timer?.cancel();
      _timer = null;
    }
    await _recorder.dispose();
  }

  /// Stops the platform recorder and resolves the raw file path exactly once.
  Future<String?> _stopNative() async {
    _timer?.cancel();
    _timer = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    final resolved = path ?? _path;
    _path = null;
    return resolved;
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
