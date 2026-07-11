import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../models/pending_outgoing_message.dart';
import 'pending_voice_preview.dart';

/// WhatsApp-style outgoing bubble while upload/send is in progress.
class PendingMessageBubble extends StatelessWidget {
  const PendingMessageBubble({
    super.key,
    required this.pending,
    this.onRetry,
  });

  final PendingOutgoingMessage pending;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final label = pending.previewLabel ?? pending.content ?? _defaultLabel(pending.type);
    final progress = pending.phase == PendingSendPhase.sending
        ? 1.0
        : pending.progress.clamp(0.0, 1.0);
    final statusText = pending.phase == PendingSendPhase.uploading
        ? 'Uploading ${(progress * 100).round()}%'
        : pending.phase == PendingSendPhase.sending
            ? 'Sending…'
            : 'Failed';
    final localPath = pending.localFilePath;
    final showImagePreview = pending.type == 'image' && localPath != null && localPath.isNotEmpty;
    final showVideoPreview = pending.type == 'video' && localPath != null && localPath.isNotEmpty;
    final showDocumentPreview = pending.type == 'document' && pending.fileName != null;
    final showVoicePreview =
        (pending.type == 'voice_note' || pending.type == 'audio') && pending.localId.isNotEmpty;

    final bubble = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.75),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showImagePreview)
                  _PendingMediaOverlay(
                    progress: progress,
                    failed: pending.phase == PendingSendPhase.failed,
                    child: Image.file(
                      File(localPath),
                      width: 220,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (showVideoPreview)
                  _PendingLocalVideoPreview(
                    filePath: localPath,
                    progress: progress,
                    failed: pending.phase == PendingSendPhase.failed,
                  ),
                if (showDocumentPreview)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _PendingDocumentCard(
                      fileName: pending.fileName!,
                      progress: progress,
                      failed: pending.phase == PendingSendPhase.failed,
                    ),
                  ),
                if (showVoicePreview)
                  PendingVoicePreview(
                    seed: pending.localId,
                    durationSeconds: pending.durationSeconds,
                    progress: progress,
                    failed: pending.phase == PendingSendPhase.failed,
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    (showImagePreview || showVideoPreview || showDocumentPreview || showVoicePreview) ? 8 : 10,
                    14,
                    10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!showImagePreview && !showVideoPreview && !showDocumentPreview && !showVoicePreview)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_iconForType(pending.type), color: Colors.white70, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (!showImagePreview && !showVideoPreview && !showDocumentPreview && !showVoicePreview) const SizedBox(height: 10),
                      if (!showImagePreview && !showVideoPreview && !showDocumentPreview && !showVoicePreview)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pending.phase == PendingSendPhase.failed ? null : progress,
                            minHeight: 4,
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          ),
                        ),
                      SizedBox(height: (showImagePreview || showVideoPreview || showDocumentPreview || showVoicePreview) ? 0 : 6),
                      Text(
                        statusText,
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (pending.phase == PendingSendPhase.failed && onRetry != null) {
      return GestureDetector(onTap: onRetry, child: bubble);
    }
    return bubble;
  }

  static String _defaultLabel(String type) {
    switch (type) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'voice_note':
      case 'audio':
        return 'Voice message';
      case 'document':
        return 'Document';
      default:
        return 'Attachment';
    }
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'image':
        return Icons.image_outlined;
      case 'video':
        return Icons.videocam_outlined;
      case 'voice_note':
      case 'audio':
        return Icons.mic_none_rounded;
      case 'document':
        return Icons.insert_drive_file_outlined;
      default:
        return Icons.attach_file;
    }
  }
}

class _PendingDocumentCard extends StatelessWidget {
  const _PendingDocumentCard({
    required this.fileName,
    required this.progress,
    required this.failed,
  });

  final String fileName;
  final double progress;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: failed ? null : progress,
                  strokeWidth: 2.5,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingMediaOverlay extends StatelessWidget {
  const _PendingMediaOverlay({
    required this.child,
    required this.progress,
    required this.failed,
  });

  final Widget child;
  final double progress;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        Container(
          width: 220,
          height: 160,
          color: Colors.black38,
          child: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                value: failed ? null : progress,
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingLocalVideoPreview extends StatefulWidget {
  const _PendingLocalVideoPreview({
    required this.filePath,
    required this.progress,
    required this.failed,
  });

  final String filePath;
  final double progress;
  final bool failed;

  @override
  State<_PendingLocalVideoPreview> createState() => _PendingLocalVideoPreviewState();
}

class _PendingLocalVideoPreviewState extends State<_PendingLocalVideoPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.file(File(widget.filePath));
    try {
      await controller.initialize();
      await controller.pause();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PendingMediaOverlay(
      progress: widget.progress,
      failed: widget.failed,
      child: SizedBox(
        width: 220,
        height: 160,
        child: _ready && _controller != null
            ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              )
            : Container(
                color: Colors.black87,
                child: const Center(
                  child: Icon(Icons.videocam_rounded, color: Colors.white54, size: 32),
                ),
              ),
      ),
    );
  }
}
