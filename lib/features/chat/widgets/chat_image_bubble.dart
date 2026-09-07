import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme/app_theme.dart';

/// Inline chat image loaded with auth headers (Image.network headers are unreliable).
class ChatImageBubble extends StatefulWidget {
  const ChatImageBubble({
    super.key,
    required this.url,
    required this.authToken,
    this.width = 240,
    this.onTap,
  });

  final String url;
  final String authToken;
  final double width;
  final VoidCallback? onTap;

  @override
  State<ChatImageBubble> createState() => _ChatImageBubbleState();
}

class _ChatImageBubbleState extends State<ChatImageBubble> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ChatImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.authToken != widget.authToken) {
      _bytes = null;
      _loading = true;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse(widget.url),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'image/*',
        },
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300 && res.bodyBytes.isNotEmpty) {
        setState(() {
          _bytes = res.bodyBytes;
          _loading = false;
          _failed = false;
        });
      } else {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: widget.width,
      child: _loading
          ? SizedBox(
              height: widget.width * 0.75,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.violet),
                ),
              ),
            )
          : _failed || _bytes == null
              ? SizedBox(
                  height: widget.width * 0.5,
                  child: Center(
                    child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade400, size: 36),
                  ),
                )
              : Image.memory(
                  _bytes!,
                  width: widget.width,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
    );

    if (widget.onTap == null) return child;
    return GestureDetector(onTap: widget.onTap, child: child);
  }
}
