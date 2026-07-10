import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/pending_outgoing_message.dart';

/// WhatsApp-style outgoing bubble while upload/send is in progress.
class PendingMessageBubble extends StatelessWidget {
  const PendingMessageBubble({
    super.key,
    required this.pending,
  });

  final PendingOutgoingMessage pending;

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

    return Padding(
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
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.file(
                        File(localPath),
                        width: 220,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        width: 220,
                        height: 160,
                        color: Colors.black38,
                        child: Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              value: pending.phase == PendingSendPhase.failed ? null : progress,
                              strokeWidth: 3,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(14, showImagePreview ? 8 : 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!showImagePreview)
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
                      if (!showImagePreview) const SizedBox(height: 10),
                      if (!showImagePreview)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pending.phase == PendingSendPhase.failed ? null : progress,
                            minHeight: 4,
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          ),
                        ),
                      SizedBox(height: showImagePreview ? 0 : 6),
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
      default:
        return Icons.attach_file;
    }
  }
}
