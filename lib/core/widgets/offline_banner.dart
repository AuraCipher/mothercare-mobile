import 'package:flutter/material.dart';

/// Slim offline hint — place below the app header, not in the status bar area.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF374151),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(width: 8),
            Text(
              'No internet connection',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
