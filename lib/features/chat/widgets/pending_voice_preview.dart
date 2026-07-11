import 'package:flutter/material.dart';

/// Static waveform bars for a pending voice note upload.
class PendingVoicePreview extends StatelessWidget {
  const PendingVoicePreview({
    super.key,
    required this.seed,
    this.durationSeconds,
    required this.progress,
    required this.failed,
  });

  final String seed;
  final String? durationSeconds;
  final double progress;
  final bool failed;

  List<double> get _bars {
    final hash = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return List<double>.generate(24, (i) {
      final v = ((hash + i * 17) % 11) + 4;
      return v.toDouble();
    });
  }

  String get _durationLabel {
    final raw = durationSeconds?.trim();
    if (raw == null || raw.isEmpty) return '0:00';
    final seconds = int.tryParse(raw.split('.').first) ?? 0;
    final minutes = seconds ~/ 60;
    final rem = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rem';
  }

  @override
  Widget build(BuildContext context) {
    final bars = _bars;
    final filledBars = (bars.length * progress.clamp(0.0, 1.0)).round();

    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Stack(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < bars.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: bars[i],
                              decoration: BoxDecoration(
                                color: i < filledBars
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: failed ? 0.35 : 0.55),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _durationLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (!failed && progress < 1)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
