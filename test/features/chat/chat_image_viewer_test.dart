import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mobile/core/media/media_store.dart';
import 'package:mobile/features/chat/widgets/chat_image_viewer_screen.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';

  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/docs';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Uint8List png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  late Directory tempRoot;
  late List<MethodCall> channelCalls;

  setUpAll(() async {
    tempRoot = await Directory.systemTemp.createTemp('mcs_viewer');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
  });

  setUp(() {
    channelCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaStore.channel, (call) async {
      channelCalls.add(call);
      return 'content://media/1';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaStore.channel, null);
  });

  tearDownAll(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  http.Client imageClient() => MockClient((_) async {
        return http.Response.bytes(
          png,
          200,
          headers: {
            'content-type': 'image/png',
            'content-disposition': "inline; filename*=UTF-8''my_photo.png",
          },
        );
      });

  Widget buildViewer(List<String> urls, {int initialIndex = 0, http.Client? client}) {
    return MaterialApp(
      home: ChatImageViewerScreen(
        urls: urls,
        authToken: 'token',
        initialIndex: initialIndex,
        httpClient: client ?? imageClient(),
      ),
    );
  }

  /// Real file IO cannot finish inside the test's fake-async zone: alternate
  /// real event-loop turns ([tester.runAsync]) with frame pumps so the save
  /// chain (download → write → channel → delete) can advance.
  Future<void> pumpWhileRunning(
    WidgetTester tester,
    bool Function() done, {
    int maxRounds = 80,
  }) async {
    for (var i = 0; i < maxRounds; i++) {
      if (done()) return;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
  }

  testWidgets('shows page indicator and starts at initialIndex', (tester) async {
    await tester.pumpWidget(buildViewer(['u0', 'u1', 'u2'], initialIndex: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('viewer-page-indicator')), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('swiping left moves to the next picture', (tester) async {
    await tester.pumpWidget(buildViewer(['u0', 'u1', 'u2']));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('single picture hides the indicator', (tester) async {
    await tester.pumpWidget(buildViewer(['u0']));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('viewer-page-indicator')), findsNothing);
    expect(find.byKey(const ValueKey('viewer-save-all')), findsNothing);
    expect(find.byKey(const ValueKey('viewer-save-current')), findsOneWidget);
  });

  testWidgets('save current stores the file with its real uploaded name', (tester) async {
    await tester.pumpWidget(buildViewer(['u0', 'u1']));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('viewer-save-current')));
    // Wait for the whole chain: channel save → temp delete (real IO) → snackbar.
    await pumpWhileRunning(
      tester,
      () => find.textContaining('Saved my_photo.png').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(channelCalls, hasLength(1));
    final args = channelCalls.single.arguments as Map;
    expect(channelCalls.single.method, 'saveMedia');
    expect(args['fileName'], 'my_photo.png');
    expect(args['mimeType'], 'image/png');
    expect(find.text('Saved my_photo.png to Gallery'), findsOneWidget);
  });

  testWidgets('save all stores every picture', (tester) async {
    await tester.pumpWidget(buildViewer(['u0', 'u1', 'u2']));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('viewer-save-all')));
    await pumpWhileRunning(
      tester,
      () => find.text('Saved 3 images to gallery').evaluate().isNotEmpty,
      maxRounds: 200,
    );
    await tester.pumpAndSettle();

    expect(channelCalls, hasLength(3));
    for (final call in channelCalls) {
      expect(call.method, 'saveMedia');
      expect((call.arguments as Map)['fileName'], 'my_photo.png');
    }
    expect(find.text('Saved 3 images to gallery'), findsOneWidget);
    expect(find.text('Saving…'), findsNothing,
        reason: 'progress dialog must be dismissed');
  });
}
