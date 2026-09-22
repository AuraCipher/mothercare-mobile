import 'package:flutter/material.dart';

import '../../../core/widgets/app_logo.dart';

/// Reusable watermark wrapper — the ONLY place the chat watermark is built.
///
/// Wrap a chat/inbox screen's existing body with this; nothing inside the
/// screen changes:
///
/// ```dart
/// body: WatermarkedChatView(
///   child: Stack(...existing content, untouched...),
/// ),
/// ```
///
/// Layering: the watermark is the FIRST [Stack] child so it paints behind
/// [child] (lists, composers, FABs, overlays). [IgnorePointer] guarantees it
/// never swallows taps. Opacity stays in the 0.04–0.06 band so bubbles and
/// text remain fully readable.
class WatermarkedChatView extends StatelessWidget {
  const WatermarkedChatView({
    super.key,
    required this.child,
    this.size = 220,
    this.opacity = 0.05,
  });

  /// The screen's existing content, shown above the watermark.
  final Widget child;

  /// Logo render size in logical pixels (fixed — never stretched full-bleed).
  final double size;

  /// Keep between 0.04 and 0.06.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: RepaintBoundary(
                child: Opacity(
                  opacity: opacity,
                  // srcIn: replace every pixel's color with black while
                  // keeping the PNG's own alpha -> grey-blackish silhouette
                  // of the logo shape; transparent background stays clear.
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Colors.black,
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      AppAssets.bglessLogo,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
