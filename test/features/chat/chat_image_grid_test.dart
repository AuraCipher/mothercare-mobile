import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/chat/widgets/chat_image_bubble.dart';
import 'package:mobile/features/chat/widgets/chat_image_grid.dart';

void main() {
  Widget harness(List<String> urls, ValueChanged<int>? onTap) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ChatImageGridBubble(
            urls: urls,
            authToken: 'token',
            onTapIndex: onTap,
          ),
        ),
      ),
    );
  }

  Finder cell(int i) => find.byKey(ValueKey('image-cell-$i'));

  testWidgets('single image renders one cell with natural aspect', (tester) async {
    await tester.pumpWidget(harness(['u0'], null));
    expect(cell(0), findsOneWidget);
    expect(find.byType(ChatImageBubble), findsOneWidget);
    expect(find.byKey(const ValueKey('image-more-count')), findsNothing);
  });

  testWidgets('two images render side by side', (tester) async {
    await tester.pumpWidget(harness(['u0', 'u1'], null));
    expect(cell(0), findsOneWidget);
    expect(cell(1), findsOneWidget);
    expect(cell(2), findsNothing);
    // Same row → same y position.
    final y0 = tester.getCenter(cell(0)).dy;
    final y1 = tester.getCenter(cell(1)).dy;
    expect(y0, y1);
  });

  testWidgets('three images: one left, two stacked right', (tester) async {
    await tester.pumpWidget(harness(['u0', 'u1', 'u2'], null));
    expect(cell(0), findsOneWidget);
    expect(cell(1), findsOneWidget);
    expect(cell(2), findsOneWidget);

    // Cell 0 is on the left half; cells 1/2 share the right column.
    expect(tester.getCenter(cell(0)).dx, lessThan(tester.getCenter(cell(1)).dx));
    expect(tester.getCenter(cell(1)).dy, lessThan(tester.getCenter(cell(2)).dy));
  });

  testWidgets('four images: 2×2 without overflow badge', (tester) async {
    await tester.pumpWidget(harness(['u0', 'u1', 'u2', 'u3'], null));
    for (var i = 0; i < 4; i++) {
      expect(cell(i), findsOneWidget);
    }
    expect(cell(4), findsNothing);
    expect(find.byKey(const ValueKey('image-more-count')), findsNothing);
  });

  testWidgets('five+ images: 2×2 with +N overlay on the last cell', (tester) async {
    await tester.pumpWidget(harness(['u0', 'u1', 'u2', 'u3', 'u4', 'u5'], null));
    for (var i = 0; i < 4; i++) {
      expect(cell(i), findsOneWidget);
    }
    expect(cell(4), findsNothing);
    expect(find.text('+2'), findsOneWidget);
    // Only the 4th cell is capped — the rest of the grid shows 4 images.
    expect(find.byType(ChatImageBubble), findsNWidgets(4));
  });

  testWidgets('tapping a cell reports its image index', (tester) async {
    int? tapped;
    await tester.pumpWidget(harness(['u0', 'u1', 'u2'], (i) => tapped = i));

    await tester.tap(cell(1));
    expect(tapped, 1);

    await tester.tap(cell(2));
    expect(tapped, 2);
  });

  testWidgets('tapping the +N overlay opens at the capped image', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      harness(['u0', 'u1', 'u2', 'u3', 'u4', 'u5'], (i) => tapped = i),
    );

    await tester.tap(find.byKey(const ValueKey('image-more-count')));
    expect(tapped, 3);
  });

  testWidgets('empty url list renders nothing', (tester) async {
    await tester.pumpWidget(harness([], null));
    expect(find.byType(ChatImageBubble), findsNothing);
    expect(find.byKey(const ValueKey('image-more-count')), findsNothing);
  });
}
