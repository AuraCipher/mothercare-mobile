import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme/app_theme.dart';

/// Full-screen image viewer with authenticated fetch.
class ChatImageViewerScreen extends StatefulWidget {
  const ChatImageViewerScreen({
    super.key,
    required this.url,
    required this.authToken,
  });

  final String url;
  final String authToken;

  @override
  State<ChatImageViewerScreen> createState() => _ChatImageViewerScreenState();
}

class _ChatImageViewerScreenState extends State<ChatImageViewerScreen> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: AppColors.violet)
            : _failed || _bytes == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined, color: Colors.grey.shade500, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Could not load image',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _failed = false;
                          });
                          _load();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.memory(_bytes!, fit: BoxFit.contain),
                  ),
      ),
    );
  }
}
