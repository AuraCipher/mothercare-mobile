import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme/app_theme.dart';
import '../data/chat_media_download.dart';

/// Full-screen swipeable image viewer with authenticated fetch.
///
/// Shows every image of a message in a [PageView] (swipe left/right like
/// WhatsApp), an "i / n" page indicator, and save actions for the current
/// picture or the whole set.
class ChatImageViewerScreen extends StatefulWidget {
  const ChatImageViewerScreen({
    super.key,
    required this.urls,
    required this.authToken,
    this.initialIndex = 0,
    this.httpClient,
  });

  final List<String> urls;
  final String authToken;
  final int initialIndex;

  /// Injectable client for tests.
  final http.Client? httpClient;

  @override
  State<ChatImageViewerScreen> createState() => _ChatImageViewerScreenState();
}

class _ChatImageViewerScreenState extends State<ChatImageViewerScreen> {
  late final PageController _pageController;
  late int _index;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _index = widget.urls.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveUrls(List<String> urls, {required String errorLabel}) async {
    if (urls.isEmpty || _saving) return;
    setState(() => _saving = true);

    // Progress dialog for multi-file saves; captured navigator so the dialog
    // is closed exactly once even if the viewer itself is popped mid-save.
    NavigatorState? dialogNav;
    if (urls.length > 1 && mounted) {
      dialogNav = Navigator.of(context, rootNavigator: true);
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _SaveProgressDialog(),
      ));
    }

    ChatMediaSaveReport? report;
    try {
      report = await saveChatMediaUrls(
        urls: urls,
        authToken: widget.authToken,
        client: widget.httpClient,
      );
    } catch (_) {
      report = null;
    } finally {
      try {
        dialogNav?.pop();
      } catch (_) {/* dialog already gone */}
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (report == null) {
      _showSnack(errorLabel);
    } else if (urls.length == 1 && report.savedCount == 1) {
      final saved = report.saved.first;
      _showSnack('Saved ${saved.fileName}${saved.isPublic ? ' to Gallery' : ''}');
    } else if (report.allSaved) {
      _showSnack('Saved ${report.savedCount} images to gallery');
    } else {
      _showSnack(
        'Saved ${report.savedCount} of ${urls.length}'
        '${report.failedCount > 0 ? ' — ${report.failedCount} failed' : ''}',
      );
    }
  }

  Future<void> _saveCurrent() async {
    final url = widget.urls[_index];
    await _saveUrls([url], errorLabel: 'Could not save image');
  }

  Future<void> _saveAll() => _saveUrls(widget.urls, errorLabel: 'Could not save images');

  @override
  Widget build(BuildContext context) {
    final showCount = widget.urls.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: showCount
            ? Text(
                '${_index + 1} / ${widget.urls.length}',
                key: const ValueKey('viewer-page-indicator'),
                style: const TextStyle(fontSize: 16, color: Colors.white),
              )
            : const SizedBox.shrink(),
        actions: [
          IconButton(
            key: const ValueKey('viewer-save-current'),
            tooltip: 'Save image',
            icon: const Icon(Icons.download_outlined),
            onPressed: _saving ? null : _saveCurrent,
          ),
          if (showCount)
            IconButton(
              key: const ValueKey('viewer-save-all'),
              tooltip: 'Save all images',
              icon: const Icon(Icons.done_all_outlined),
              onPressed: _saving ? null : _saveAll,
            ),
        ],
      ),
      body: widget.urls.isEmpty
          ? const Center(child: Text('Could not load image', style: TextStyle(color: Colors.grey)))
          : PageView.builder(
              controller: _pageController,
              itemCount: widget.urls.length,
              onPageChanged: (i) {
                if (mounted) setState(() => _index = i);
              },
              itemBuilder: (context, i) => _ViewerImagePage(
                key: ValueKey('viewer-page-$i'),
                url: widget.urls[i],
                authToken: widget.authToken,
                httpClient: widget.httpClient,
              ),
            ),
    );
  }
}

class _SaveProgressDialog extends StatelessWidget {
  const _SaveProgressDialog();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Card(
        color: Color(0xFF2A2A2A),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.violet),
              SizedBox(height: 14),
              Text('Saving…', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewerImagePage extends StatefulWidget {
  const _ViewerImagePage({
    super.key,
    required this.url,
    required this.authToken,
    this.httpClient,
  });

  final String url;
  final String authToken;
  final http.Client? httpClient;

  @override
  State<_ViewerImagePage> createState() => _ViewerImagePageState();
}

class _ViewerImagePageState extends State<_ViewerImagePage>
    with AutomaticKeepAliveClientMixin {
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final owned = widget.httpClient ?? http.Client();
      late final http.Response res;
      try {
        res = await owned
            .get(
              Uri.parse(widget.url),
              headers: {
                'Authorization': 'Bearer ${widget.authToken}',
                'Accept': 'image/*',
              },
            )
            .timeout(const Duration(seconds: 15));
      } finally {
        if (widget.httpClient == null) owned.close();
      }
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
    super.build(context);
    return Center(
      child: _loading
          ? const CircularProgressIndicator(color: AppColors.violet)
          : _failed || _bytes == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, color: Colors.grey.shade500, size: 48),
                    const SizedBox(height: 12),
                    Text('Could not load image', style: TextStyle(color: Colors.grey.shade400)),
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
    );
  }
}
