import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/chat_models.dart';
import '../utils/chat_media_url.dart';

enum ChatMessageAction { save, saveAll, saveSelected, saveSingle, edit, delete }

List<ChatMessageAction> availableMessageActions({
  required ChatMessage message,
  required bool isMine,
  required bool canPost,
}) {
  if (message.isDeleted) return const [];

  final actions = <ChatMessageAction>[];
  final media = message.displayAttachments;
  final hasMedia = media.any((m) => m.hasContent || m.id.isNotEmpty);

  if (hasMedia) {
    if (media.length > 1) {
      // Multi-attachment messages get the WhatsApp-style save trio.
      actions.add(ChatMessageAction.saveAll);
      actions.add(ChatMessageAction.saveSelected);
      actions.add(ChatMessageAction.saveSingle);
    } else {
      actions.add(ChatMessageAction.save);
    }
  }

  if (isMine && canPost) {
    actions.add(ChatMessageAction.delete);
    if (message.type == 'text' && !hasMedia && message.content != null && message.content!.trim().isNotEmpty) {
      actions.add(ChatMessageAction.edit);
    }
  }

  return actions;
}

Future<ChatMessageAction?> showChatMessageActionsSheet(
  BuildContext context, {
  required List<ChatMessageAction> actions,
  ChatMessage? message,
}) {
  if (actions.isEmpty) return Future.value(null);

  return showModalBottomSheet<ChatMessageAction>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            ListTile(
              leading: Icon(_iconForAction(action), color: action == ChatMessageAction.delete ? AppColors.error : null),
              title: Text(
                _labelForAction(action, message),
                style: TextStyle(
                  color: action == ChatMessageAction.delete ? AppColors.error : AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => Navigator.pop(ctx, action),
            ),
        ],
      ),
    ),
  );
}

/// Bottom sheet to pick which attachments to save: a grid of thumbnails with
/// checkmarks. Returns selected indexes in original order, or `null` when
/// cancelled. With [allowMultiple] false it behaves as a single-choice picker
/// (the "Save single" flow).
Future<List<int>?> showSaveSelectionSheet(
  BuildContext context, {
  required List<ChatMessageMedia> medias,
  required String authToken,
  bool allowMultiple = true,
}) {
  final selected = <int>{};

  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final thumb = ((MediaQuery.sizeOf(ctx).width - 16 - 3 * 8) / 4).clamp(64.0, 120.0);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  allowMultiple ? 'Select images to save' : 'Select one to save',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < medias.length; i++)
                          _SelectionThumb(
                            key: ValueKey('save-selection-$i'),
                            media: medias[i],
                            authToken: authToken,
                            size: thumb,
                            selected: selected.contains(i),
                            onTap: () {
                              setSheetState(() {
                                if (!allowMultiple) {
                                  selected
                                    ..clear()
                                    ..add(i);
                                  return;
                                }
                                if (!selected.remove(i)) selected.add(i);
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('save-selection-confirm'),
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(ctx, selected.toList()..sort()),
                        child: Text('Save (${selected.length})'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _SelectionThumb extends StatelessWidget {
  const _SelectionThumb({
    super.key,
    required this.media,
    required this.authToken,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final ChatMessageMedia media;
  final String authToken;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (media.isImage) {
      child = _ThumbImage(url: resolveChatMediaUrl(media), authToken: authToken, size: size);
    } else {
      child = Container(
        width: size,
        height: size,
        color: AppColors.surface,
        child: Icon(
          media.isVideo
              ? Icons.videocam_outlined
              : media.isAudio
                  ? Icons.mic_none
                  : Icons.insert_drive_file_outlined,
          color: AppColors.textMuted,
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            child,
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? AppColors.violet : Colors.white,
                shadows: selected
                    ? null
                    : const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbImage extends StatelessWidget {
  const _ThumbImage({required this.url, required this.authToken, required this.size});

  final String url;
  final String authToken;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: AppColors.surface,
        child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
      );
    }
    // Reuses the auth-aware bubble as a fixed square thumbnail.
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        headers: {'Authorization': 'Bearer $authToken', 'Accept': 'image/*'},
        errorBuilder: (_, _, _) => Container(
          color: AppColors.surface,
          child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
        ),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : Container(color: AppColors.surface),
      ),
    );
  }
}

IconData _iconForAction(ChatMessageAction action) {
  switch (action) {
    case ChatMessageAction.save:
    case ChatMessageAction.saveSingle:
      return Icons.download_rounded;
    case ChatMessageAction.saveAll:
      return Icons.done_all_rounded;
    case ChatMessageAction.saveSelected:
      return Icons.select_all_rounded;
    case ChatMessageAction.edit:
      return Icons.edit_outlined;
    case ChatMessageAction.delete:
      return Icons.delete_outline_rounded;
  }
}

String _labelForAction(ChatMessageAction action, ChatMessage? message) {
  final count = message?.displayAttachments.length ?? 0;
  switch (action) {
    case ChatMessageAction.save:
      return 'Save to device';
    case ChatMessageAction.saveAll:
      return 'Save all ($count)';
    case ChatMessageAction.saveSelected:
      return 'Save selected…';
    case ChatMessageAction.saveSingle:
      return 'Save single…';
    case ChatMessageAction.edit:
      return 'Edit message';
    case ChatMessageAction.delete:
      return 'Delete message';
  }
}
