import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/chat/models/chat_models.dart';
import 'package:mobile/features/chat/widgets/chat_message_actions_sheet.dart';

ChatMessageSender _sender() =>
    const ChatMessageSender(id: 'u1', name: 'Asha', role: 'teacher');

ChatMessageMedia _image(String id) =>
    ChatMessageMedia(id: id, mimeType: 'image/webp', url: '');

ChatMessage _message({
  String type = 'image',
  List<ChatMessageMedia> attachments = const [],
  ChatMessageMedia? mediaFile,
}) {
  return ChatMessage(
    id: 'm1',
    roomId: 'r1',
    type: type,
    content: null,
    sender: _sender(),
    createdAt: DateTime(2026, 10, 9, 10),
    mediaFile: mediaFile,
    attachments: attachments,
  );
}

void main() {
  group('availableMessageActions', () {
    test('multi-image message offers the save trio (no plain save)', () {
      final message = _message(
        attachments: [_image('a'), _image('b'), _image('c')],
        mediaFile: _image('a'),
      );
      final actions = availableMessageActions(
        message: message,
        isMine: false,
        canPost: true,
      );

      expect(actions, contains(ChatMessageAction.saveAll));
      expect(actions, contains(ChatMessageAction.saveSelected));
      expect(actions, contains(ChatMessageAction.saveSingle));
      expect(actions, isNot(contains(ChatMessageAction.save)));
      expect(actions, isNot(contains(ChatMessageAction.delete)));
    });

    test('single-image message keeps the plain save action', () {
      final message = _message(attachments: [_image('a')], mediaFile: _image('a'));
      final actions = availableMessageActions(
        message: message,
        isMine: false,
        canPost: true,
      );

      expect(actions, [ChatMessageAction.save]);
    });

    test('legacy message with only mediaFile still offers saving', () {
      final message = _message(mediaFile: _image('a'));
      final actions = availableMessageActions(
        message: message,
        isMine: false,
        canPost: true,
      );
      expect(actions, contains(ChatMessageAction.save));
    });

    test('two documents also get the trio', () {
      final message = _message(
        type: 'document',
        attachments: const [
          ChatMessageMedia(id: 'd1', mimeType: 'application/pdf', url: ''),
          ChatMessageMedia(id: 'd2', mimeType: 'application/pdf', url: ''),
        ],
      );
      final actions = availableMessageActions(
        message: message,
        isMine: false,
        canPost: true,
      );
      expect(actions, contains(ChatMessageAction.saveAll));
      expect(actions, contains(ChatMessageAction.saveSelected));
    });

    test('text-only message has no save actions', () {
      final message = _message(type: 'text');
      final actions = availableMessageActions(
        message: message,
        isMine: true,
        canPost: true,
      );
      expect(actions, isNot(contains(ChatMessageAction.save)));
      expect(actions, isNot(contains(ChatMessageAction.saveAll)));
    });

    test('deleted message has no actions', () {
      final message = ChatMessage(
        id: 'm1',
        roomId: 'r1',
        type: 'image',
        sender: _sender(),
        createdAt: DateTime(2026, 10, 9),
        isDeleted: true,
        attachments: [_image('a'), _image('b')],
      );
      expect(
        availableMessageActions(message: message, isMine: true, canPost: true),
        isEmpty,
      );
    });
  });

  testWidgets('sheet labels show save all with attachment count', (tester) async {
    final message = _message(
      attachments: [_image('a'), _image('b'), _image('c')],
      mediaFile: _image('a'),
    );
    final actions = availableMessageActions(
      message: message,
      isMine: false,
      canPost: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showChatMessageActionsSheet(
                context,
                actions: actions,
                message: message,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Save all (3)'), findsOneWidget);
    expect(find.text('Save selected…'), findsOneWidget);
    expect(find.text('Save single…'), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
    expect(find.byIcon(Icons.select_all_rounded), findsOneWidget);
  });

  testWidgets('selection sheet selects and confirms indexes', (tester) async {
    final medias = [_image('a'), _image('b'), _image('c')];
    List<int>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showSaveSelectionSheet(
                  context,
                  medias: medias,
                  authToken: 'token',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Confirm is disabled with nothing selected.
    final confirm = find.byKey(const ValueKey('save-selection-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('save-selection-0')));
    await tester.tap(find.byKey(const ValueKey('save-selection-2')));
    await tester.pumpAndSettle();

    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(result, [0, 2]);
  });

  testWidgets('single-select sheet keeps exactly one choice', (tester) async {
    final medias = [_image('a'), _image('b')];
    List<int>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showSaveSelectionSheet(
                  context,
                  medias: medias,
                  authToken: 'token',
                  allowMultiple: false,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-selection-0')));
    await tester.tap(find.byKey(const ValueKey('save-selection-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-selection-confirm')));
    await tester.pumpAndSettle();

    expect(result, [1]);
  });
}
