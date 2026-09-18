import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../uploads/upload_task.dart';
import '../data/chat_attachment_queue.dart';

/// Pending-attachment tray above the composer. Renders ONLY from M3
/// [UploadTask] snapshots delivered by [ChatAttachmentQueue] (single source
/// of truth); never computes its own progress. Self-contained polling-free
/// updates via [ListenableBuilder] so the message list never rebuilds on
/// chunk progress (§28).
class ChatAttachmentTray extends StatelessWidget {
  const ChatAttachmentTray({
    super.key,
    required this.queue,
    required this.onSend,
  });

  final ChatAttachmentQueue queue;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        if (queue.isEmpty) return const SizedBox.shrink();
        final tray = queue.tray;
        return Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tray.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final entry = tray[index];
                    return _AttachmentTile(
                      queue: queue,
                      taskId: entry.item.taskId,
                      kind: entry.item.kind,
                      fileName: entry.item.fileName,
                      task: entry.task,
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              _SendRow(queue: queue, onSend: onSend),
            ],
          ),
        );
      },
    );
  }
}

class _SendRow extends StatelessWidget {
  const _SendRow({required this.queue, required this.onSend});

  final ChatAttachmentQueue queue;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final pending = queue.pendingSend;
    final failedSend = pending?.state == PendingSendState.failed;
    return Row(
      children: [
        Expanded(
          child: Text(
            failedSend && pending?.error != null ? pending!.error! : queue.statusText(),
            style: TextStyle(
              fontSize: 12,
              color: failedSend ? AppColors.error : AppColors.textMuted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (failedSend)
          TextButton(
            onPressed: () async {
              try {
                await queue.retrySend();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('Retry send'),
          )
        else
          FilledButton.tonal(
            onPressed: queue.canSend
                ? () async {
                    try {
                      await onSend();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    }
                  }
                : null,
            child: queue.isSending
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send'),
          ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.queue,
    required this.taskId,
    required this.kind,
    required this.fileName,
    required this.task,
  });

  final ChatAttachmentQueue queue;
  final String taskId;
  final String kind;
  final String fileName;
  final UploadTask? task;

  @override
  Widget build(BuildContext context) {
    final state = task?.state;
    final progress = task?.progress ?? 0.0;
    final failed = state == UploadTaskState.failed || state == UploadTaskState.expired;
    final done = state == UploadTaskState.completed;
    final active = state != null &&
        (state == UploadTaskState.uploading ||
            state == UploadTaskState.queued ||
            state == UploadTaskState.retryWait ||
            state == UploadTaskState.creatingSession ||
            state == UploadTaskState.ready ||
            state == UploadTaskState.completing);

    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: failed ? AppColors.error : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 56, width: 88, child: _preview(context)),
              if (active || (!done && !failed))
                LinearProgressIndicator(value: done ? 1 : progress, minHeight: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  failed
                      ? 'Failed'
                      : done
                          ? 'Ready'
                          : '${(progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10,
                    color: failed ? AppColors.error : AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _TileAction(
              failed: failed,
              done: done,
              active: active,
              onRemove: () => queue.removeAttachment(taskId),
              onRetry: () => queue.retryAttachment(taskId),
              onCancel: () => queue.removeAttachment(taskId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(BuildContext context) {
    if (kind == 'image' && task != null) {
      final file = File(task!.localPath);
      return Image.file(file,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined));
    }
    final icon = kind == 'video'
        ? Icons.videocam_rounded
        : kind == 'voice'
            ? Icons.mic_rounded
            : Icons.insert_drive_file_outlined;
    return Container(
      color: AppColors.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: AppColors.textMuted),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(fileName,
                style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _TileAction extends StatelessWidget {
  const _TileAction({
    required this.failed,
    required this.done,
    required this.active,
    required this.onRemove,
    required this.onRetry,
    required this.onCancel,
  });

  final bool failed;
  final bool done;
  final bool active;
  final VoidCallback onRemove;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _circleBtn(context, Icons.refresh_rounded, onRetry),
          _circleBtn(context, Icons.close_rounded, onRemove),
        ],
      );
    }
    return _circleBtn(context, Icons.close_rounded, active ? onCancel : onRemove);
  }

  Widget _circleBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: Icon(icon, size: 13, color: Colors.white),
      ),
    );
  }
}
