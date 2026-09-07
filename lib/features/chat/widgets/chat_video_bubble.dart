import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';

/// Inline chat video with play overlay — opens fullscreen player on tap.
class ChatVideoBubble extends StatefulWidget {
  const ChatVideoBubble({
    super.key,
    required this.url,
    required this.authToken,
    this.width = 240,
  });

  final String url;
  final String authToken;
  final double width;

  @override
  State<ChatVideoBubble> createState() => _ChatVideoBubbleState();
}

class _ChatVideoBubbleState extends State<ChatVideoBubble> {
  VideoPlayerController? _thumbController;
  bool _initialized = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initThumb();
  }

  Future<void> _initThumb() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: {'Authorization': 'Bearer ${widget.authToken}'},
    );
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _thumbController = controller;
        _initialized = true;
      });
    } catch (_) {
      controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _thumbController?.dispose();
    super.dispose();
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenVideoPlayer(
          url: widget.url,
          authToken: widget.authToken,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openFullscreen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: widget.width,
          height: widget.width * 0.56,
          color: Colors.black87,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_initialized && _thumbController != null)
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _thumbController!.value.size.width,
                      height: _thumbController!.value.size.height,
                      child: VideoPlayer(_thumbController!),
                    ),
                  ),
                )
              else if (_failed)
                const Center(
                  child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 32),
                )
              else
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  ),
                ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenVideoPlayer extends StatefulWidget {
  const _FullscreenVideoPlayer({required this.url, required this.authToken});

  final String url;
  final String authToken;

  @override
  State<_FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<_FullscreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: {'Authorization': 'Bearer ${widget.authToken}'},
    );
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: Colors.grey.shade500, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load video',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _failed = false;
                        _ready = false;
                      });
                      _controller.dispose();
                      _controller = VideoPlayerController.networkUrl(
                        Uri.parse(widget.url),
                        httpHeaders: {'Authorization': 'Bearer ${widget.authToken}'},
                      );
                      _controller.initialize().then((_) {
                        if (!mounted) return;
                        setState(() => _ready = true);
                        _controller.play();
                      }).catchError((_) {
                        if (mounted) setState(() => _failed = true);
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              )
            : _ready
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const CircularProgressIndicator(color: AppColors.violet),
      ),
      floatingActionButton: _ready
          ? FloatingActionButton(
              backgroundColor: AppColors.violet,
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
              child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )
          : null,
    );
  }
}
