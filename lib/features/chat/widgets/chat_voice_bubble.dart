import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/app_theme.dart';

/// Inline voice message with play/pause and scrub bar.
class ChatVoiceBubble extends StatefulWidget {
  const ChatVoiceBubble({
    super.key,
    required this.url,
    required this.authToken,
    this.foregroundColor = AppColors.textPrimary,
    this.accentColor = AppColors.violet,
  });

  final String url;
  final String authToken;
  final Color foregroundColor;
  final Color accentColor;

  @override
  State<ChatVoiceBubble> createState() => _ChatVoiceBubbleState();
}

class _ChatVoiceBubbleState extends State<ChatVoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _ready = false;
  bool _loading = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

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
        unawaited(_player.seek(Duration.zero));
        unawaited(_player.pause());
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureSource() async {
    if (_ready) return;
    setState(() {
      _loading = true;
      _error = null;
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load voice message';
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
      await _player.play();
    }
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
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _duration.inMilliseconds > 0 ? _progress : null,
                  minHeight: 4,
                  backgroundColor: fg.withValues(alpha: 0.2),
                  color: accent,
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
