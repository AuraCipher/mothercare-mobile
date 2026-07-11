import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/chat_models.dart';

enum ChatMessageAction { save, edit, delete }

List<ChatMessageAction> availableMessageActions({
  required ChatMessage message,
  required bool isMine,
  required bool canPost,
}) {
  if (message.isDeleted) return const [];

  final actions = <ChatMessageAction>[];
  final hasMedia = message.mediaFile != null && message.mediaFile!.id.isNotEmpty;

  if (hasMedia) {
    actions.add(ChatMessageAction.save);
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
                _labelForAction(action),
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

IconData _iconForAction(ChatMessageAction action) {
  switch (action) {
    case ChatMessageAction.save:
      return Icons.download_rounded;
    case ChatMessageAction.edit:
      return Icons.edit_outlined;
    case ChatMessageAction.delete:
      return Icons.delete_outline_rounded;
  }
}

String _labelForAction(ChatMessageAction action) {
  switch (action) {
    case ChatMessageAction.save:
      return 'Save to device';
    case ChatMessageAction.edit:
      return 'Edit message';
    case ChatMessageAction.delete:
      return 'Delete message';
  }
}
