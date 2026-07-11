import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../../config/app_config.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../data/upload_api.dart';
import '../../../core/storage/chat_message_cache_store.dart';
import '../../../core/storage/pending_outgoing_store.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/universal_header.dart';
import '../models/chat_models.dart';
import '../models/pending_outgoing_message.dart';
import '../widgets/chat_document_bubble.dart';
import '../widgets/chat_image_bubble.dart';
import '../widgets/chat_video_bubble.dart';
import '../widgets/chat_voice_bubble.dart';
import '../widgets/chat_composer_bar.dart';
import '../widgets/pending_message_bubble.dart';
import '../widgets/voice_note_recorder.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.session,
    required this.socket,
    required this.room,
    this.groupLabel,
    this.academicYearId,
    this.branchId,
  });

  final StoredSession session;
  final ChatSocketService socket;
  final ChatRoomSummary room;
  final String? groupLabel;
  final String? academicYearId;
  final String? branchId;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _chatApi = ChatApi();
  final _uploadApi = UploadApi();
  final _messageCache = ChatMessageCacheStore.instance;
  final _pendingStore = PendingOutgoingStore.instance;
  final _picker = ImagePicker();
  final _voiceRecorder = VoiceNoteRecorder();
  final _composer = TextEditingController();
  final _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  final List<PendingOutgoingMessage> _pending = [];
  String? _awaitingSocketPendingId;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;
  bool _messagesOffline = false;
  double _voiceLockDragUp = 0;
  late final String _userId;
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _userId = widget.session.payload.id;
    _voiceRecorder.onTick = (_) {
      if (mounted) setState(() {});
    };
    widget.socket.joinRoom(widget.room.id);
    widget.socket.markRead(roomId: widget.room.id);
    _messageSub = widget.socket.onMessage.listen(_onSocketMessage);
    _errorSub = widget.socket.onError.listen(_onSocketError);
    _scrollController.addListener(_onScroll);
    _hydrateFromCache().then((_) => _loadMessages());
  }

  @override
  void dispose() {
    _persistPending();
    _messageSub?.cancel();
    _errorSub?.cancel();
    _voiceRecorder.dispose();
    _scrollController.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onSocketMessage(ChatMessage message) {
    if (message.roomId != widget.room.id) return;
    if (_messages.any((m) => m.id == message.id)) return;
    final me = widget.session.payload.id;
    setState(() {
      _messages.add(message);
      if (message.sender.id == me && _awaitingSocketPendingId != null) {
        _pending.removeWhere((p) => p.localId == _awaitingSocketPendingId);
        _awaitingSocketPendingId = null;
      }
    });
    widget.socket.markRead(roomId: widget.room.id, messageId: message.id);
    _persistMessages();
    _persistPending();
    _scrollToBottom();
  }

  void _onSocketError(String message) {
    if (!mounted) return;
    if (_awaitingSocketPendingId != null) {
      _markPendingFailed(_awaitingSocketPendingId!);
      _awaitingSocketPendingId = null;
      if (mounted) setState(() => _sending = false);
    }
    _showError(message);
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || !_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 80) {
      _loadMore();
    }
  }

  Future<void> _hydrateFromCache() async {
    final cached = await _messageCache.loadRoom(userId: _userId, roomId: widget.room.id);
    final pending = await _pendingStore.loadRoom(userId: _userId, roomId: widget.room.id);
    if (!mounted) return;

    final restoredPending = <PendingOutgoingMessage>[];
    for (final item in pending) {
      if (item.hasPersistableFile) {
        final path = item.localFilePath;
        if (path == null || !await File(path).exists()) continue;
      }
      restoredPending.add(item);
    }

    setState(() {
      if (cached != null && cached.messages.isNotEmpty) {
        _messages
          ..clear()
          ..addAll(cached.messages);
        _cursor = cached.cursor;
        _hasMore = cached.hasMore;
        _loading = false;
      }
      if (restoredPending.isNotEmpty) {
        _pending
          ..clear()
          ..addAll(restoredPending);
      }
    });
  }

  Future<void> _persistMessages() {
    return _messageCache.saveRoom(
      userId: _userId,
      roomId: widget.room.id,
      messages: _messages,
      cursor: _cursor,
      hasMore: _hasMore,
    );
  }

  Future<void> _persistPending() {
    return _pendingStore.saveRoom(
      userId: _userId,
      roomId: widget.room.id,
      pending: _pending,
    );
  }

  Future<void> _loadMessages() async {
    if (_messages.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final messages = await _chatApi.fetchMessages(
        token: widget.session.token,
        roomId: widget.room.id,
      );
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _loading = false;
        _messagesOffline = false;
        _error = null;
        _hasMore = messages.length >= 40;
        _cursor = messages.isNotEmpty ? messages.first.createdAt.toUtc().toIso8601String() : null;
      });
      await _persistMessages();
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_messages.isNotEmpty) {
        setState(() {
          _messagesOffline = true;
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (_messages.isNotEmpty) {
        setState(() {
          _messagesOffline = true;
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _error = 'Could not load messages';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final older = await _chatApi.fetchMessages(
        token: widget.session.token,
        roomId: widget.room.id,
        cursor: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, older);
        _loadingMore = false;
        _hasMore = older.length >= 40;
        if (older.isNotEmpty) {
          _cursor = older.first.createdAt.toUtc().toIso8601String();
        } else {
          _hasMore = false;
        }
      });
      await _persistMessages();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _sendText() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending || !widget.room.canPost) return;

    setState(() => _sending = true);
    _composer.clear();
    widget.socket.sendMessage(roomId: widget.room.id, content: text);
    if (mounted) setState(() => _sending = false);
  }

  Future<double?> _videoDurationSeconds(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      return controller.value.duration.inMilliseconds / 1000.0;
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }

  Future<void> _sendMedia({
    required File file,
    required String fileName,
    required String purpose,
    required String messageType,
    String? durationSeconds,
    String? previewLabel,
    String? mimeType,
  }) async {
    final ayId = widget.academicYearId;
    if (ayId == null || ayId.isEmpty) {
      _showError('Academic year is required for attachments');
      return;
    }
    if (!widget.room.canPost) return;

    final localId = 'local-${DateTime.now().millisecondsSinceEpoch}';
    final persistedPath = await _pendingStore.persistMediaFile(
      userId: _userId,
      localId: localId,
      source: file,
    );
    final pending = PendingOutgoingMessage(
      localId: localId,
      type: messageType,
      previewLabel: previewLabel,
      localFilePath: persistedPath ?? file.path,
      fileName: fileName,
      purpose: purpose,
      durationSeconds: durationSeconds,
      academicYearId: ayId,
    );
    setState(() {
      _pending.add(pending);
      _sending = true;
    });
    await _persistPending();
    _scrollToBottom();

    try {
      final uploaded = await _uploadApi.uploadChatFile(
        token: widget.session.token,
        file: file,
        fileName: fileName,
        roomId: widget.room.id,
        academicYearId: ayId,
        purpose: purpose,
        durationSeconds: durationSeconds,
        mimeType: mimeType,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            final idx = _pending.indexWhere((m) => m.localId == localId);
            if (idx >= 0) {
              _pending[idx] = _pending[idx].copyWith(progress: p);
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        final idx = _pending.indexWhere((m) => m.localId == localId);
        if (idx >= 0) {
          _pending[idx] = _pending[idx].copyWith(progress: 1, phase: PendingSendPhase.sending);
        }
      });
      widget.socket.sendMessage(
        roomId: widget.room.id,
        type: messageType,
        mediaFileId: uploaded.id,
      );
      _awaitingSocketPendingId = localId;
      await _persistPending();
    } on ApiException catch (e) {
      _markPendingFailed(localId);
      _awaitingSocketPendingId = null;
      _showError(e.message);
    } catch (_) {
      _markPendingFailed(localId);
      _awaitingSocketPendingId = null;
      _showError('Failed to upload attachment');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _markPendingFailed(String localId) {
    setState(() {
      final idx = _pending.indexWhere((m) => m.localId == localId);
      if (idx >= 0) {
        _pending[idx] = _pending[idx].copyWith(phase: PendingSendPhase.failed);
      }
    });
    _persistPending();
  }

  Future<void> _retryPending(PendingOutgoingMessage pending) async {
    if (pending.phase != PendingSendPhase.failed || _sending) return;
    final path = pending.localFilePath;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) {
      _showError('Attachment file is no longer available');
      return;
    }
    setState(() {
      _pending.removeWhere((p) => p.localId == pending.localId);
    });
    await _sendMedia(
      file: file,
      fileName: pending.fileName ?? p.basename(path),
      purpose: pending.purpose ?? 'chat',
      messageType: pending.type,
      durationSeconds: pending.durationSeconds,
      previewLabel: pending.previewLabel,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final file = File(picked.path);
    await _sendMedia(
      file: file,
      fileName: picked.name,
      purpose: 'chat',
      messageType: 'image',
      previewLabel: 'Photo',
    );
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    final duration = await _videoDurationSeconds(file);
    if (duration == null) {
      _showError('Could not read video file');
      return;
    }
    if (duration > 120) {
      _showError('Videos must be 2 minutes or shorter');
      return;
    }
    await _sendMedia(
      file: file,
      fileName: picked.name,
      purpose: 'video',
      messageType: 'video',
      durationSeconds: duration.toStringAsFixed(1),
      previewLabel: 'Video',
    );
  }

  Future<void> _startVoiceRecording() async {
    final ok = await _voiceRecorder.start();
    if (!ok) {
      _showError('Microphone permission is required for voice notes');
      return;
    }
    _voiceLockDragUp = 0;
    if (mounted) setState(() {});
  }

  void _onVoicePointerMove(PointerMoveEvent event) {
    if (_voiceRecorder.phase != VoiceRecorderPhase.recording) return;
    _voiceLockDragUp -= event.delta.dy;
    if (_voiceLockDragUp > 72) {
      _voiceRecorder.lock();
      HapticFeedback.lightImpact();
      _voiceLockDragUp = 0;
      if (mounted) setState(() {});
    }
  }

  Future<void> _onVoicePointerUp() async {
    if (_voiceRecorder.phase == VoiceRecorderPhase.recording) {
      await _finishVoiceRecording(send: true);
    }
    _voiceLockDragUp = 0;
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    if (_voiceRecorder.phase == VoiceRecorderPhase.idle) return;
    if (!send) {
      await _voiceRecorder.cancel();
      if (mounted) setState(() {});
      return;
    }
    final elapsed = _voiceRecorder.elapsed;
    final file = await _voiceRecorder.finish();
    if (mounted) setState(() {});
    if (file == null) return;
    await _sendMedia(
      file: file,
      fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      purpose: 'voice_note',
      messageType: 'voice_note',
      durationSeconds: elapsed.inSeconds > 0 ? elapsed.inSeconds.toString() : '1',
      previewLabel: 'Voice message',
      mimeType: 'audio/mp4',
    );
  }

  Future<void> _pickDocument() async {
    final picked = await FilePicker.platform.pickFiles(withReadStream: false);
    if (picked == null || picked.files.isEmpty) return;
    final platformFile = picked.files.single;
    final path = platformFile.path;
    if (path == null) return;
    final file = File(path);
    await _sendMedia(
      file: file,
      fileName: platformFile.name,
      purpose: 'chat',
      messageType: 'document',
      previewLabel: platformFile.name,
      mimeType: platformFile.extension != null ? _guessMime(platformFile.extension!) : null,
    );
  }

  String? _guessMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return null;
    }
  }

  void _showAttachmentSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Document'),
              onTap: () {
                Navigator.pop(ctx);
                _pickDocument();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  String _mediaUrl(ChatMessage message) {
    final url = message.mediaFile?.url ?? '';
    if (url.startsWith('http')) return url;
    if (url.isNotEmpty) return '${AppConfig.apiBaseUrl}$url';
    if (message.mediaFile?.id.isNotEmpty == true) {
      return '${AppConfig.apiBaseUrl}/api/uploads/${message.mediaFile!.id}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.session.payload.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: Stack(
        children: [
          Column(
            children: [
              UniversalHeader(
                title: widget.room.name,
                showBack: true,
              ),
              if (_voiceRecorder.phase != VoiceRecorderPhase.idle)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: AppColors.violet.withValues(alpha: 0.06),
                  child: Text(
                    _voiceRecorder.phase == VoiceRecorderPhase.locked
                        ? 'Recording locked — tap send or delete'
                        : 'Recording… release to send',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: AppColors.violet, fontWeight: FontWeight.w500),
                  ),
                ),
              if (_messagesOffline) const OfflineBanner(),
              if (!widget.room.canPost)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.surface,
                  child: const Text(
                    'Read-only channel',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              Expanded(child: _buildMessageList(me)),
              if (widget.room.canPost) _buildComposer(),
            ],
          ),
          if (_voiceRecorder.phase == VoiceRecorderPhase.recording)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerMove: _onVoicePointerMove,
                onPointerUp: (_) => _onVoicePointerUp(),
                onPointerCancel: (_) => _onVoicePointerUp(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageList(String myUserId) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.violet));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadMessages, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_messages.isEmpty && _pending.isEmpty) {
      return const Center(
        child: Text('No messages yet', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + _pending.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_loadingMore && index == _messages.length + _pending.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final pendingCount = _pending.length;
        if (index < pendingCount) {
          final pending = _pending[pendingCount - 1 - index];
          return PendingMessageBubble(
            pending: pending,
            onRetry: pending.phase == PendingSendPhase.failed
                ? () => _retryPending(pending)
                : null,
          );
        }
        final msgIndex = index - pendingCount;
        final message = _messages[_messages.length - 1 - msgIndex];
        final isMine = message.sender.id == myUserId;
        return _MessageBubble(
          message: message,
          isMine: isMine,
          mediaUrl: _mediaUrl(message),
          authToken: widget.session.token,
        );
      },
    );
  }

  Widget _buildComposer() {
    final recording = _voiceRecorder.phase != VoiceRecorderPhase.idle;
    return ChatComposerBar(
      controller: _composer,
      enabled: widget.room.canPost,
      sending: _sending,
      isRecording: recording,
      isLocked: _voiceRecorder.phase == VoiceRecorderPhase.locked,
      recordElapsed: _voiceRecorder.elapsed,
      onAttach: _showAttachmentSheet,
      onCamera: () => _pickPhoto(ImageSource.camera),
      onSendText: _sendText,
      onRecordStart: _startVoiceRecording,
      onLockedSend: () => _finishVoiceRecording(send: true),
      onRecordCancel: () => _finishVoiceRecording(send: false),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.mediaUrl,
    required this.authToken,
  });

  final ChatMessage message;
  final bool isMine;
  final String mediaUrl;
  final String authToken;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('h:mm a').format(message.createdAt.toLocal());
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isMine ? AppColors.violet : AppColors.surface;
    final fg = isMine ? Colors.white : AppColors.textPrimary;
    final isImage = message.isImageMessage && mediaUrl.isNotEmpty;
    final showCaption = message.isImageMessage && message.hasCaption;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                message.sender.name,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
              ),
            ),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
            clipBehavior: isImage ? Clip.antiAlias : Clip.none,
            padding: isImage ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
              border: isMine ? null : Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isImage)
                  ChatImageBubble(
                    url: mediaUrl,
                    authToken: authToken,
                  )
                else if (message.type == 'voice_note' ||
                    message.type == 'audio' ||
                    message.mediaFile?.isAudio == true)
                  mediaUrl.isNotEmpty
                      ? ChatVoiceBubble(
                          url: mediaUrl,
                          authToken: authToken,
                          foregroundColor: fg,
                          accentColor: isMine ? Colors.white : AppColors.violet,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mic_rounded, color: fg, size: 20),
                            const SizedBox(width: 8),
                            Text('Voice message', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                          ],
                        )
                else if (message.mediaFile?.isVideo == true || message.type == 'video')
                  mediaUrl.isNotEmpty
                      ? ChatVideoBubble(url: mediaUrl, authToken: authToken)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_rounded, color: fg, size: 20),
                            const SizedBox(width: 8),
                            Text('Video', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                          ],
                        )
                else if (message.isDocumentMessage && mediaUrl.isNotEmpty)
                  ChatDocumentBubble(
                    url: mediaUrl,
                    authToken: authToken,
                    fileName: message.documentFileName,
                    foregroundColor: fg,
                    accentColor: isMine ? Colors.white : AppColors.violet,
                  )
                else if (message.displayText.isNotEmpty)
                  Text(message.displayText, style: TextStyle(color: fg, fontSize: 15, height: 1.35)),
                if (showCaption)
                  Padding(
                    padding: EdgeInsets.fromLTRB(isImage ? 10 : 0, isImage ? 6 : 4, isImage ? 10 : 0, 0),
                    child: Text(
                      message.content!.trim(),
                      style: TextStyle(color: fg, fontSize: 15, height: 1.35),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(isImage ? 10 : 0, 4, isImage ? 10 : 0, isImage ? 8 : 0),
                  child: Text(
                    time,
                    style: TextStyle(fontSize: 10, color: isMine ? Colors.white70 : AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
