import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_file_api.dart';

/// How a failed voice load should be presented (backend restriction vs a
/// transient fault) — classified by probing the file's metadata endpoint
/// rather than guessing from player error codes (which differ per platform).
enum VoiceLoadFailure { denied, transient }

typedef VoiceAccessProbe = Future<VoiceLoadFailure> Function(
  String url,
  String authToken,
);

/// Inline voice message: play/pause, deterministic waveform, tap-to-seek,
/// and classified load errors with retry. Seeks only ever move within a
/// KNOWN duration (real playback position, never a fabricated scrub).
class ChatVoiceBubble extends StatefulWidget {
  const ChatVoiceBubble({
    super.key,
    required this.url,
    required this.authToken,
    this.foregroundColor = AppColors.textPrimary,
    this.accentColor = AppColors.violet,
    this.player,
    this.probeAccess,
  });

  final String url;
  final String authToken;
  final Color foregroundColor;
  final Color accentColor;

  /// Injectable for tests (just_audio's real player needs a platform).
  final AudioPlayer? player;

  /// Injectable for tests (defaults to a ChatFileApi metadata probe).
  final VoiceAccessProbe? probeAccess;

  @override
  State<ChatVoiceBubble> createState() => _ChatVoiceBubbleState();
}

class _ChatVoiceBubbleState extends State<ChatVoiceBubble> {
  /// One voice note plays at a time, like every messenger: starting this
  /// bubble pauses whichever bubble was last active.
  static _ChatVoiceBubbleState? _activePlayback;

  late final AudioPlayer _player = widget.player ?? AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _ready = false;
  bool _loading = false;
  String? _error;
  bool _errorRetryable = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  static const double _waveWidth = 140;
  static const double _waveHeight = 26;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.positionStream.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _durationSub = _player.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _loading = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
      });
      if (state.processingState == ProcessingState.completed) {
        // Real end-of-playback: rewind to start (progress returns to zero)
        // and pause so the next tap plays from the beginning.
        unawaited(_player.seek(Duration.zero));
        unawaited(_player.pause());
      }
    });
  }

  @override
  void dispose() {
    if (identical(_activePlayback, this)) _activePlayback = null;
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// URL shape is `${api}/api/uploads/<fileId>` (chat_media_url.dart).
  static String? _fileIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segs = uri.pathSegments;
    final i = segs.indexOf('uploads');
    if (i >= 0 && i + 1 < segs.length && segs[i + 1].isNotEmpty) {
      return segs[i + 1];
    }
    return null;
  }

  /// Default probe: metadata GET with the same auth as playback. 403/404
  /// there ⇒ the backend truly denies this user (no point retrying); any
  /// other outcome (network, 5xx, meta-OK-but-audio-failed) ⇒ transient.
  Future<VoiceLoadFailure> _classifyFailure() {
    final probe = widget.probeAccess;
    if (probe != null) return probe(widget.url, widget.authToken);
    final fileId = _fileIdFromUrl(widget.url);
    if (fileId == null) return Future.value(VoiceLoadFailure.transient);
    return ChatFileApi()
        .getFileMeta(token: widget.authToken, fileId: fileId)
        .then<VoiceLoadFailure>((_) => VoiceLoadFailure.transient)
        .catchError((Object e) {
      if (e is ApiException && (e.statusCode == 404 || e.statusCode == 403)) {
        return VoiceLoadFailure.denied;
      }
      return VoiceLoadFailure.transient;
    });
  }

  Future<void> _ensureSource() async {
    if (_ready) return;
    setState(() {
      _loading = true;
      _error = null;
      _errorRetryable = false;
    });
    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(widget.url),
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'audio/*',
          },
        ),
      );
      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
      });
    } catch (_) {
      final failure = await _classifyFailure();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure == VoiceLoadFailure.denied
            ? 'Voice message is not available'
            : 'Could not load voice message';
        _errorRetryable = failure != VoiceLoadFailure.denied;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_error != null) return;
    await _ensureSource();
    if (_error != null || !_ready) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      final previous = _activePlayback;
      _activePlayback = this;
      if (previous != null && !identical(previous, this)) {
        await previous._pauseIfPlaying();
      }
      await _player.play();
    }
  }

  Future<void> _pauseIfPlaying() async {
    if (_player.playing) {
      await _player.pause();
    }
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _errorRetryable = false;
    });
    await _ensureSource();
  }

  /// Tap or drag on the waveform: seeks to the touched FRACTION of the
  /// real duration. No-ops until the duration is known (never fakes it).
  void _seekTo(double dx) {
    if (!_ready || _duration <= Duration.zero) return;
    final fraction = (dx / _waveWidth).clamp(0.0, 1.0);
    _player.seek(Duration(
      milliseconds: (fraction * _duration.inMilliseconds).round(),
    ));
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double get _progress {
    if (_duration.inMilliseconds <= 0) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Deterministic per-URL bars — same algorithm as PendingVoicePreview, so
  /// a note's waveform looks identical in pending, sent, and received state.
  List<double> get _bars {
    final hash = widget.url.codeUnits.fold<int>(0, (a, b) => a + b);
    return List<double>.generate(24, (i) {
      final v = ((hash + i * 17) % 11) + 4;
      return v.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.foregroundColor;
    final accent = widget.accentColor;
    final playing = _player.playing;

    if (_error != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: fg, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(_error!, style: TextStyle(color: fg, fontSize: 13)),
          ),
          if (_errorRetryable)
            IconButton(
              onPressed: _retry,
              tooltip: 'Retry',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.refresh_rounded, color: fg, size: 16),
            ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: playing ? accent : accent.withValues(alpha: 0.2),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _loading ? null : _togglePlayback,
            child: SizedBox(
              width: 40,
              height: 40,
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                    )
                  : Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: playing ? Colors.white : fg,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: _waveWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _seekTo(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => _seekTo(d.localPosition.dx),
                child: SizedBox(
                  key: const ValueKey('voice-waveform'),
                  width: _waveWidth,
                  height: _waveHeight,
                  child: CustomPaint(
                    painter: _VoiceWavePainter(
                      bars: _bars,
                      progress: _progress,
                      playedColor: accent,
                      trackColor: fg.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _duration.inMilliseconds > 0
                    ? '${_format(_position)} / ${_format(_duration)}'
                    : 'Voice message',
                style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter({
    required this.bars,
    required this.progress,
    required this.playedColor,
    required this.trackColor,
  });

  final List<double> bars;
  final double progress;
  final Color playedColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final slot = size.width / bars.length;
    final barWidth = (slot * 0.55).clamp(1.5, 3.0);
    final playedCount = bars.length * progress;
    for (var i = 0; i < bars.length; i++) {
      final height = (bars[i] / 14.0) * size.height;
      final x = i * slot + (slot - barWidth) / 2;
      final rect = Rect.fromLTWH(
        x,
        (size.height - height) / 2,
        barWidth,
        height,
      );
      final paint = Paint()
        ..color = i < playedCount ? playedColor : trackColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VoiceWavePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.playedColor != playedColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.bars != bars;
}
