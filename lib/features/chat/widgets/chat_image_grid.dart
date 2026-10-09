import 'package:flutter/material.dart';

import 'chat_image_bubble.dart';

/// WhatsApp-style image grid for chat messages.
///
/// Layouts (total [width], square cells, 3px gaps):
///  * 1 image  → natural single image
///  * 2 images → side by side
///  * 3 images → one large left, two stacked right
///  * 4 images → 2×2
///  * 5+       → 2×2 with a dark overlay "+N" on the last cell
///
/// Tapping a cell reports its message-wide image index through
/// [onTapIndex] so the viewer can open on the right picture.
class ChatImageGridBubble extends StatelessWidget {
  const ChatImageGridBubble({
    super.key,
    required this.urls,
    required this.authToken,
    this.width = 240,
    this.onTapIndex,
  });

  final List<String> urls;
  final String authToken;
  final double width;
  final ValueChanged<int>? onTapIndex;

  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    if (urls.length == 1) {
      return ChatImageBubble(
        key: const ValueKey('image-cell-0'),
        url: urls[0],
        authToken: authToken,
        width: width,
        onTap: () => onTapIndex?.call(0),
      );
    }

    final side = (width - _gap) / 2;

    if (urls.length == 2) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _cell(0, side),
          const SizedBox(width: _gap),
          _cell(1, side),
        ],
      );
    }

    if (urls.length == 3) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cell(0, side),
          const SizedBox(width: _gap),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _cell(1, side),
              const SizedBox(height: _gap),
              _cell(2, side),
            ],
          ),
        ],
      );
    }

    // 4 and beyond: 2×2, last cell carries the "+N" overflow overlay.
    final moreCount = urls.length - 4;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cell(0, side),
            const SizedBox(width: _gap),
            _cell(1, side),
          ],
        ),
        const SizedBox(height: _gap),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cell(2, side),
            const SizedBox(width: _gap),
            _cell(3, side, showMore: moreCount > 0 ? moreCount : null),
          ],
        ),
      ],
    );
  }

  Widget _cell(int index, double side, {int? showMore}) {
    if (index >= urls.length) return SizedBox(width: side, height: side);
    final image = ChatImageBubble(
      key: ValueKey('image-cell-$index'),
      url: urls[index],
      authToken: authToken,
      width: side,
      height: side,
      onTap: () => onTapIndex?.call(index),
    );
    if (showMore == null) return image;
    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          Positioned.fill(
            child: GestureDetector(
              onTap: () => onTapIndex?.call(index),
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: Text(
                  '+$showMore',
                  key: const ValueKey('image-more-count'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
