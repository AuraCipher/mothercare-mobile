import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// WhatsApp-style floating action button for starting a new DM.
class NewMessageFab extends StatelessWidget {
  const NewMessageFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onTap,
      backgroundColor: AppColors.violet,
      foregroundColor: Colors.white,
      elevation: 4,
      tooltip: 'New message',
      child: const Icon(Icons.add_rounded, size: 28),
    );
  }
}
