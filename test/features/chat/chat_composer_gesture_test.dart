import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/chat/widgets/chat_composer_bar.dart';
import 'package:mobile/features/chat/widgets/voice_note_recorder.dart';

/// Mirrors the chat-room wiring (chat_room_screen.dart): composer callbacks
/// drive the same phase machine, and an AbsorbPointer overlay blocks new
/// pointers while a finger is held on the mic. This is the structural
/// equivalent of the production gesture path — Flutter dispatches pointer
/// events along the hit path cached at PointerDown, exactly as in the app.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _controller = TextEditingController();
  VoiceRecorderPhase phase = VoiceRecorderPhase.idle;
  Offset origin = Offset.zero;
  bool cancelArmed = false;

  int startCalls = 0;
  int sendOnRelease = 0;
  int cancelOnRelease = 0;
  int pointerCancels = 0;
  int backgroundTaps = 0;

  // Thresholds kept in sync with chat_room_screen.dart.
  static const double _lockDragUp = 72;
  static const double _cancelDragLeft = 96;

  Future<void> _onRecordStart(LongPressStartDetails details) async {
    if (phase != VoiceRecorderPhase.idle) return;
    origin = details.globalPosition;
    setState(() {
      phase = VoiceRecorderPhase.recording;
      startCalls++;
    });
  }

  void _onRecordMove(LongPressMoveUpdateDetails details) {
    if (phase != VoiceRecorderPhase.recording) return;
    final pos = details.globalPosition;
    if (origin.dy - pos.dy > _lockDragUp) {
      setState(() {
        phase = VoiceRecorderPhase.locked;
        cancelArmed = false;
      });
      return;
    }
    final armed = pos.dx - origin.dx <= -_cancelDragLeft;
    if (armed != cancelArmed) {
      setState(() => cancelArmed = armed);
    }
  }

  void _onRecordEnd() {
    if (phase == VoiceRecorderPhase.recording) {
      setState(() {
        if (cancelArmed) {
          cancelOnRelease++;
        } else {
          sendOnRelease++;
        }
        cancelArmed = false;
        phase = VoiceRecorderPhase.idle;
      });
    }
    // locked → lift is ignored (hands-free continues), idle → nothing.
  }

  void _onRecordPointerCancel() {
    if (phase == VoiceRecorderPhase.recording) {
      setState(() {
        pointerCancels++;
        cancelArmed = false;
        phase = VoiceRecorderPhase.idle;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => backgroundTaps++),
                    child: const Center(child: Text('messages')),
                  ),
                ),
                ChatComposerBar(
                  controller: _controller,
                  enabled: true,
                  sending: false,
                  isRecording: phase != VoiceRecorderPhase.idle,
                  isLocked: phase == VoiceRecorderPhase.locked,
                  recordElapsed: Duration.zero,
                  onAttach: () {},
                  onCamera: () {},
                  onSendText: () {},
                  onRecordStart: _onRecordStart,
                  onRecordMove: _onRecordMove,
                  onRecordEnd: _onRecordEnd,
                  onRecordPointerCancel: _onRecordPointerCancel,
                  onLockedSend: () {},
                  onRecordCancel: () {},
                ),
              ],
            ),
            if (phase == VoiceRecorderPhase.recording)
              const Positioned.fill(child: AbsorbPointer()),
          ],
        ),
      ),
    );
  }
}

void main() {
  Future<TestGesture> holdMic(WidgetTester tester) async {
    // Explicit pointer id so the test can dispatch a matching cancel later.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      pointer: 42,
    );
    // Long-press acceptance (500 ms) plus margin.
    await tester.pump(const Duration(milliseconds: 600));
    return gesture;
  }

  testWidgets(
      'hold → record → release sends without any Send tap (release-to-send)',
      (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    final gesture = await holdMic(tester);
    expect(state.phase, VoiceRecorderPhase.recording);
    expect(state.startCalls, 1);

    await gesture.up();
    await tester.pump();

    expect(state.sendOnRelease, 1);
    expect(state.phase, VoiceRecorderPhase.idle);
    // No manual Send interaction existed in this test — release alone sent.
  });

  testWidgets('mic subtree stays mounted for the whole gesture '
      '(element identity preserved — the original bug)', (tester) async {
    await tester.pumpWidget(const _Harness());

    final micBefore = tester.element(find.byIcon(Icons.mic_none_rounded));

    final gesture = await holdMic(tester);
    // Recording overlay is showing (lock hint present) while held.
    expect(find.text('Slide up to lock'), findsOneWidget);
    final micDuring = tester.element(find.byIcon(Icons.mic_none_rounded));
    expect(identical(micBefore, micDuring), isTrue,
        reason: 'the mic widget must not unmount during recording, or the '
            'held pointer loses its hit path and move/end events die');

    await gesture.up();
    await tester.pump();
    final micAfter = tester.element(find.byIcon(Icons.mic_none_rounded));
    expect(identical(micBefore, micAfter), isTrue);
  });

  testWidgets('short tap does not start a recording', (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();

    expect(state.startCalls, 0);
    expect(state.phase, VoiceRecorderPhase.idle);
  });

  testWidgets('slide up locks; lifting while locked does NOT send',
      (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    final gesture = await holdMic(tester);
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(state.phase, VoiceRecorderPhase.locked);

    await gesture.up();
    await tester.pump();

    expect(state.phase, VoiceRecorderPhase.locked,
        reason: 'locked recording is hands-free — release must not send or '
            'cancel it');
    expect(state.sendOnRelease, 0);
    expect(state.cancelOnRelease, 0);
    expect(find.byTooltip('Send recording'), findsOneWidget);
    expect(find.byTooltip('Cancel recording'), findsOneWidget);
  });

  testWidgets('slide left arms cancel; release discards instead of sending',
      (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    final gesture = await holdMic(tester);
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(state.cancelArmed, isTrue);

    await gesture.up();
    await tester.pump();

    expect(state.cancelOnRelease, 1);
    expect(state.sendOnRelease, 0);
    expect(state.phase, VoiceRecorderPhase.idle);
  });

  testWidgets('system pointer cancel while recording never sends',
      (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    await holdMic(tester);
    expect(state.phase, VoiceRecorderPhase.recording);

    // The exact production failure path: a cancel delivered to the held
    // pointer's cached hit path (mic subtree Listener), NOT a pointer-up.
    await tester.sendEventToBinding(PointerCancelEvent(
      pointer: 42,
      kind: PointerDeviceKind.touch,
    ));
    await tester.pump();

    expect(state.pointerCancels, 1);
    expect(state.sendOnRelease, 0);
    expect(state.phase, VoiceRecorderPhase.idle);
  });

  testWidgets('new taps are absorbed while holding, release still sends',
      (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    final gesture = await holdMic(tester);
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    expect(state.backgroundTaps, 0, reason: 'overlay must block new pointers');

    await gesture.up();
    await tester.pump();
    expect(state.sendOnRelease, 1);
  });

  testWidgets('composer keeps a stable height in both states', (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    final heightIdle = tester.getSize(
      find.byType(ChatComposerBar),
    ).height;

    final gesture = await holdMic(tester);
    final heightRecording = tester.getSize(
      find.byType(ChatComposerBar),
    ).height;

    expect(heightRecording, heightIdle,
        reason: 'the pill must not resize under a held finger');

    await gesture.up();
    await tester.pump();
    expect(state.phase, VoiceRecorderPhase.idle);
  });
}
