import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

typedef RecordMoveCallback = void Function(LongPressMoveUpdateDetails details);

/// WhatsApp-style chat composer — white pill with attach, camera, mic, send.
class ChatComposerBar extends StatefulWidget {
  const ChatComposerBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.isRecording,
    required this.isLocked,
    required this.recordElapsed,
    required this.onAttach,
    required this.onCamera,
    required this.onSendText,
    required this.onRecordStart,
    required this.onRecordMove,
    required this.onRecordEnd,
    required this.onLockedSend,
    required this.onRecordCancel,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final bool isRecording;
  final bool isLocked;
  final Duration recordElapsed;
  final VoidCallback onAttach;
  final VoidCallback onCamera;
  final VoidCallback onSendText;
  final Future<void> Function() onRecordStart;
  final RecordMoveCallback onRecordMove;
  final Future<void> Function() onRecordEnd;
  final VoidCallback onLockedSend;
  final VoidCallback onRecordCancel;

  @override
  State<ChatComposerBar> createState() => _ChatComposerBarState();
}

class _ChatComposerBarState extends State<ChatComposerBar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.isRecording ? _buildRecordingBar() : _buildIdleBar(),
        ),
      ),
    );
  }

  Widget _buildIdleBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          _iconBtn(
            icon: Icons.attach_file_rounded,
            onTap: widget.enabled && !widget.sending ? widget.onAttach : null,
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              enabled: widget.enabled && !widget.sending,
              textInputAction: TextInputAction.send,
              onSubmitted: widget.enabled ? (_) => widget.onSendText() : null,
              style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Message...',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          _iconBtn(
            icon: Icons.photo_camera_outlined,
            onTap: widget.enabled && !widget.sending ? widget.onCamera : null,
          ),
          _micButton(),
          _iconBtn(
            icon: Icons.send_rounded,
            onTap: widget.enabled && !widget.sending && _hasText ? widget.onSendText : null,
            color: _hasText ? AppColors.textPrimary : AppColors.textMuted.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (widget.isLocked)
            _iconBtn(icon: Icons.delete_outline_rounded, onTap: widget.onRecordCancel, color: AppColors.error)
          else
            const SizedBox(width: 40),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: Tween<double>(begin: 0.35, end: 1).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _formatElapsed(widget.recordElapsed),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PulseBars(animation: _pulse),
                ),
              ],
            ),
          ),
          if (widget.isLocked)
            _iconBtn(
              icon: Icons.send_rounded,
              onTap: widget.onLockedSend,
              color: AppColors.violet,
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textMuted.withValues(alpha: 0.7)),
                  const SizedBox(height: 2),
                  Text(
                    'Slide up to lock',
                    style: TextStyle(fontSize: 9, color: AppColors.textMuted.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _micButton() {
    return GestureDetector(
      onLongPressStart: widget.enabled && !widget.sending
          ? (_) async {
              HapticFeedback.mediumImpact();
              await widget.onRecordStart();
            }
          : null,
      onLongPressMoveUpdate: widget.isRecording && !widget.isLocked ? widget.onRecordMove : null,
      onLongPressEnd: widget.isRecording && !widget.isLocked
          ? (_) async {
              await widget.onRecordEnd();
            }
          : null,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(
          Icons.mic_none_rounded,
          size: 22,
          color: widget.isRecording ? AppColors.violet : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 22, color: color ?? AppColors.textPrimary),
      ),
    );
  }
}

class _PulseBars extends StatelessWidget {
  const _PulseBars({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(12, (i) {
            final phase = (animation.value + i * 0.08) % 1.0;
            final h = 6 + (phase * 14);
            return Container(
              width: 3,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: AppColors.violet.withValues(alpha: 0.35 + phase * 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
