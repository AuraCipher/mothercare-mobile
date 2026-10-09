import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:mobile/features/chat/widgets/chat_voice_bubble.dart';

class FakeAudioPlayer extends AudioPlayer {
  final posCtl = StreamController<Duration>.broadcast();
  final durCtl = StreamController<Duration?>.broadcast();
  final stateCtl = StreamController<PlayerState>.broadcast();

  bool playingFlag = false;
  int playCalls = 0;
  int pauseCalls = 0;
  int disposeCalls = 0;
  final seeks = <Duration?>[];
  UriAudioSource? source;
  bool failNextLoad = false;

  @override
  bool get playing => playingFlag;

  @override
  Stream<Duration> get positionStream => posCtl.stream;

  @override
  Stream<Duration?> get durationStream => durCtl.stream;

  @override
  Stream<PlayerState> get playerStateStream => stateCtl.stream;

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    if (failNextLoad) {
      failNextLoad = false;
      throw Exception('player load failed');
    }
    source = audioSource as UriAudioSource;
    durCtl.add(const Duration(seconds: 30));
    stateCtl.add(PlayerState(false, ProcessingState.ready));
    return const Duration(seconds: 30);
  }

  @override
  Future<void> play() async {
    playCalls++;
    playingFlag = true;
    stateCtl.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playingFlag = false;
    stateCtl.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks.add(position);
    posCtl.add(position ?? Duration.zero);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await posCtl.close();
    await durCtl.close();
    await stateCtl.close();
  }
}

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const url = 'https://api.test/api/uploads/file-1';
  const token = 'tok-123';

  testWidgets('play loads the source with the auth header', (tester) async {
    final fake = FakeAudioPlayer();
    await tester.pumpWidget(wrap(ChatVoiceBubble(
      url: url,
      authToken: token,
      player: fake,
      probeAccess: (u, t) async => VoiceLoadFailure.transient,
    )));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    expect(fake.source, isNotNull);
    expect(fake.source!.uri.toString(), url);
    expect(fake.source!.headers?['Authorization'], 'Bearer $token');
    expect(fake.playCalls, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('second tap pauses a playing note', (tester) async {
    final fake = FakeAudioPlayer();
    await tester.pumpWidget(wrap(ChatVoiceBubble(
      url: url,
      authToken: token,
      player: fake,
      probeAccess: (u, t) async => VoiceLoadFailure.transient,
    )));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();

    expect(fake.pauseCalls, 1);
    expect(fake.playCalls, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('progress shows real position/duration from the player',
      (tester) async {
    final fake = FakeAudioPlayer();
    await tester.pumpWidget(wrap(ChatVoiceBubble(
      url: url,
      authToken: token,
      player: fake,
      probeAccess: (u, t) async => VoiceLoadFailure.transient,
    )));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    fake.posCtl.add(const Duration(seconds: 15));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList(),
      contains('0:15 / 0:30'),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('completion rewinds to zero and pauses (progress resets)',
      (tester) async {
    final fake = FakeAudioPlayer();
    await tester.pumpWidget(wrap(ChatVoiceBubble(
      url: url,
      authToken: token,
      player: fake,
      probeAccess: (u, t) async => VoiceLoadFailure.transient,
    )));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    fake.posCtl.add(const Duration(seconds: 30));
    await tester.pump();

    fake.stateCtl.add(PlayerState(true, ProcessingState.completed));
    await tester.pumpAndSettle();

    expect(fake.seeks, contains(Duration.zero));
    expect(fake.pauseCalls, greaterThanOrEqualTo(1));
    expect(find.text('0:00 / 0:30'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('tapping the waveform seeks to that fraction of real duration',
      (tester) async {
    final fake = FakeAudioPlayer();
    await tester.pumpWidget(wrap(ChatVoiceBubble(
      url: url,
      authToken: token,
      player: fake,
      probeAccess: (u, t) async => VoiceLoadFailure.transient,
    )));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    final topLeft = tester.getTopLeft(find.byKey(const ValueKey('voice-waveform')));
    final size = tester.getSize(find.byKey(const ValueKey('voice-waveform')));
    // Tap the horizontal midpoint of the waveform.
    await tester.tapAt(Offset(topLeft.dx + size.width / 2, topLeft.dy + size.height / 2));
    await tester.pump();

    expect(fake.seeks, isNotEmpty);
    final seeked = fake.seeks.last!;
    expect(seeked.inMilliseconds, greaterThanOrEqualTo(14000));
    expect(seeked.inMilliseconds, lessThanOrEqualTo(16000)); // 15s ± rounding

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('starting a second bubble pauses the first (single active player)',
      (tester) async {
    final first = FakeAudioPlayer();
    final second = FakeAudioPlayer();
    await tester.pumpWidget(wrap(Column(
      children: [
        ChatVoiceBubble(
          url: 'https://api.test/api/uploads/file-a',
          authToken: token,
          player: first,
          probeAccess: (u, t) async => VoiceLoadFailure.transient,
        ),
        ChatVoiceBubble(
          url: 'https://api.test/api/uploads/file-b',
          authToken: token,
          player: second,
          probeAccess: (u, t) async => VoiceLoadFailure.transient,
        ),
      ],
    )));

    final bubbles = find.byType(ChatVoiceBubble);
    await tester.tap(find.descendant(
        of: bubbles.at(0), matching: find.byIcon(Icons.play_arrow_rounded)));
    await tester.pumpAndSettle();
    expect(first.playCalls, 1);

    await tester.tap(find.descendant(
        of: bubbles.at(1), matching: find.byIcon(Icons.play_arrow_rounded)));
    await tester.pumpAndSettle();

    expect(second.playCalls, 1);
    expect(first.pauseCalls, greaterThanOrEqualTo(1),
        reason: 'only one voice note may play at a time');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('backend denial (probe 404/403) shows a permanent error, no retry',
      (tester) async {
    final fake = FakeAudioPlayer()..failNextLoad = true;
    await tester.pumpWidget(wrap(ChatVoiceBubble(
      url: url,
      authToken: token,
      player: fake,
      probeAccess: (u, t) async => VoiceLoadFailure.denied,
    )));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Voice message is not available'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing,
        reason: 'retrying an authorization denial is pointless');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('transient failure shows retry; retry recovers', (tester) async {
    final fake = FakeAudioPlayer()..failNextLoad = true;
    await tester.pumpWidget(wrap(ChatVoiceBubble(
      url: url,
      authToken: token,
      player: fake,
      probeAccess: (u, t) async => VoiceLoadFailure.transient,
    )));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Could not load voice message'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();

    expect(fake.source, isNotNull, reason: 'retry reloads the source');
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('bubble disposes its player (resource cleanup)', (tester) async {
    final fake = FakeAudioPlayer();
    await tester.pumpWidget(wrap(ChatVoiceBubble(
      url: url,
      authToken: token,
      player: fake,
      probeAccess: (u, t) async => VoiceLoadFailure.transient,
    )));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(fake.disposeCalls, 1);
  });
}
