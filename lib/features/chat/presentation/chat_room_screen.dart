import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_api.dart';
import '../data/chat_attachment_queue.dart';
import '../data/chat_file_api.dart';
import '../data/chat_socket_service.dart';
import '../data/chat_upload_pool.dart';
import '../data/send_intent_store.dart';
import '../data/text_send_queue.dart';
import '../../../core/storage/chat_message_cache_store.dart';
import '../../../core/storage/pending_outgoing_store.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/universal_header.dart';
import '../models/chat_models.dart';
import '../widgets/chat_attachment_tray.dart';
import '../widgets/chat_document_bubble.dart';
import '../widgets/chat_image_bubble.dart';
import '../widgets/chat_video_bubble.dart';
import '../widgets/chat_voice_bubble.dart';
import '../data/chat_media_download.dart';
import '../utils/chat_media_url.dart';
import '../widgets/chat_image_viewer_screen.dart';
import '../widgets/chat_message_actions_sheet.dart';
import '../widgets/chat_composer_bar.dart';
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
  final _messageCache = ChatMessageCacheStore.instance;
  final _pendingStore = PendingOutgoingStore.instance;
  final _picker = ImagePicker();
  final _voiceRecorder = VoiceNoteRecorder();
  final _composer = TextEditingController();
  final _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  ChatAttachmentQueue? _queue;
  TextSendQueue? _textQueue;
  StreamSubscription<void>? _connectSub;
  bool _loading = true;
  bool _loadingMore = false;
  bool _textSending = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;
  bool _messagesOffline = false;
  double _voiceLockDragUp = 0;
  late final String _userId;
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<String>? _deletedSub;
  StreamSubscription<ChatMessage>? _updatedSub;
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
    _deletedSub = widget.socket.onMessageDeleted.listen(_onSocketMessageDeleted);
    _updatedSub = widget.socket.onMessageUpdated.listen(_onSocketMessageUpdated);
    _errorSub = widget.socket.onError.listen(_onSocketError);
    _connectSub = widget.socket.onConnect.listen((_) => _onSocketConnect());
    _scrollController.addListener(_onScroll);
    _hydrateFromCache().then((_) => _loadMessages());
    _initAttachmentQueue();
    _initTextQueue();
  }

  /// M9: durable offline text queue (same intent machinery as attachments).
  /// Recovers persisted intents now and on every reconnect.
  void _initTextQueue() {
    final queue = TextSendQueue(
      socket: widget.socket,
      getToken: () => SessionStorage().getToken(),
      userId: _userId,
      roomId: widget.room.id,
    );
    queue.addListener(_onTextQueueChanged);
    _textQueue = queue;
    queue.recover().catchError((_) {});
  }

  void _onTextQueueChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onSocketConnect() async {
    try {
      await _textQueue?.recover();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  /// M4: per-room attachment queue over the shared M3 scheduler. Legacy
  /// single-shot pending rows are purged (see _hydrateFromCache).
  Future<void> _initAttachmentQueue() async {
    final ayId = widget.academicYearId;
    if (ayId == null || ayId.isEmpty) return;
    final scheduler = ChatUploadPool.acquire(
      userId: _userId,
      getToken: () => SessionStorage().getToken(),
    );
    final queue = ChatAttachmentQueue(
      scheduler: scheduler,
      socket: widget.socket,
      files: ChatFileApi(),
      getToken: () => SessionStorage().getToken(),
      userId: _userId,
      roomId: widget.room.id,
      academicYearId: ayId,
    );
    _queue = queue;
    try {
      await queue.recover();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _queue?.dispose();
    _queue = null;
    _textQueue?.removeListener(_onTextQueueChanged);
    _textQueue?.dispose();
    _textQueue = null;
    _connectSub?.cancel();
    _messageSub?.cancel();
    _deletedSub?.cancel();
    _updatedSub?.cancel();
    _errorSub?.cancel();
    _voiceRecorder.dispose();
    _scrollController.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onSocketMessage(ChatMessage message) {
    if (message.roomId != widget.room.id) return;
    if (_messages.any((m) => m.id == message.id)) return;
    setState(() {
      _messages.add(message);
    });
    widget.socket.markRead(roomId: widget.room.id, messageId: message.id);
    _persistMessages();
    _scrollToBottom();
  }

  void _onSocketMessageDeleted(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    setState(() {
      _messages[idx] = _messages[idx].copyWith(isDeleted: true, content: null);
    });
    _persistMessages();
  }

  void _onSocketMessageUpdated(ChatMessage message) {
    if (message.roomId != widget.room.id) return;
    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return;
    setState(() {
      _messages[idx] = _messages[idx].copyWith(
        content: message.content,
        isDeleted: message.isDeleted,
      );
    });
    _persistMessages();
  }

  void _onSocketError(String message) {
    if (!mounted) return;
    // M4: attachment sends use ack callbacks (errors surface on the send
    // attempt itself). Broadcast errors remain informational only.
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
    // M4 migration: legacy single-shot pending rows belong to the retired
    // upload path. The M3 task store is now authoritative for pending work
    // (recovered via the attachment queue), so drop the legacy rows instead
    // of resurrecting them as failed ghosts.
    try {
      await _pendingStore.deleteRoom(userId: _userId, roomId: widget.room.id);
    } catch (_) {}
    if (!mounted) return;

    setState(() {
      if (cached != null && cached.messages.isNotEmpty) {
        _messages
          ..clear()
          ..addAll(cached.messages);
        _cursor = cached.cursor;
        _hasMore = cached.hasMore;
        _loading = false;
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
      setState(() {
        _loadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load older messages')),
      );
    }
  }

  Future<void> _sendText() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _textSending || !widget.room.canPost) return;
    final queue = _textQueue;
    if (queue == null) return;

    setState(() => _textSending = true);
    _composer.clear();
    try {
      final message = await queue.sendText(text);
      if (!mounted) return;
      if (!_messages.any((m) => m.id == message.id)) {
        setState(() => _messages.add(message));
        _persistMessages();
        _scrollToBottom();
      }
    } on ChatSendException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.uncertain
              ? 'Send timed out — kept for retry. Tap Retry to reconcile.'
              : 'Message saved — will send when online. Tap Retry to send now.'),
          action: SnackBarAction(label: 'Retry', onPressed: _retryPendingTexts),
        ),
      );
    } finally {
      if (mounted) setState(() => _textSending = false);
    }
  }

  /// Retry every failed/uncertain pending text with its SAME key (idempotent).
  Future<void> _retryPendingTexts() async {
    final queue = _textQueue;
    if (queue == null) return;
    for (final pending in queue.pendings) {
      if (pending.state == SendIntentState.failed ||
          pending.state == SendIntentState.uncertain) {
        try {
          final message = await queue.retryText(pending.clientMessageId);
          if (!mounted) return;
          if (!_messages.any((m) => m.id == message.id)) {
            setState(() => _messages.add(message));
            _persistMessages();
            _scrollToBottom();
          }
        } on ChatSendException {
          // Intent persists with updated state; tile shows Retry again.
        }
      }
    }
    if (mounted) setState(() {});
  }

  /// M4: sends the queue's settled attachments as ONE message (selection
  /// order) with the composer text as caption. Uploads were already done by
  /// M3 — this only creates the message, idempotently (same key on retry).
  Future<void> _sendAttachments() async {
    final queue = _queue;
    if (queue == null) return;
    final caption = _composer.text.trim();
    if (caption.isNotEmpty) _composer.clear();
    try {
      final message = await queue.send(
        caption: caption.isEmpty ? null : caption,
      );
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == message.id)) {
          _messages.add(message);
        }
      });
      await _persistMessages();
      _scrollToBottom();
    } on AttachmentLimitException catch (e) {
      _showError(e.message);
    } on StateError catch (e) {
      _showError(e.message);
    } catch (e) {
      // ChatSendException text is already user-safe; leave the failed send
      // in the tray for explicit retry (same clientMessageId).
      _showError(e.toString());
      if (caption.isNotEmpty) _composer.text = caption;
    }
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

  static const int _maxDocumentBytes = 20 * 1024 * 1024; // 20 MB
  // M5: no MB product cap for voice (duration ≤10 min is authoritative,
  // server-probed). 1 GiB is the shared infrastructure object ceiling.
  static const int _maxVoiceBytes = 1024 * 1024 * 1024;
  static const int _maxVideoBytes = 1024 * 1024 * 1024; // 1 GiB

  /// Guards shared by every picker: room context + per-file size caps.
  /// The backend remains authoritative; these only fail fast with UX copy.
  Future<File?> _guardAttachment(File file, int maxBytes) async {
    final ayId = widget.academicYearId;
    if (ayId == null || ayId.isEmpty) {
      _showError('Academic year is required for attachments');
      return null;
    }
    if (!widget.room.canPost) return null;
    if (_queue == null) {
      _showError('Attachments are not ready yet');
      return null;
    }
    final fileSize = await file.length();
    if (fileSize > maxBytes) {
      final maxMB = maxBytes ~/ (1024 * 1024);
      _showError('File too large (max ${maxMB}MB)');
      return null;
    }
    return file;
  }

  Future<void> _enqueuePhoto(File file, String fileName) async {
    final ok = await _guardAttachment(file, _maxDocumentBytes);
    if (ok == null) return;
    try {
      await _queue!.attachPhotos([(file: ok, name: fileName, mime: 'image/jpeg')]);
      _scrollToBottom();
    } on AttachmentLimitException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not add photo');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static const double _maxImageDim = 2048; // Max width/height for chat images

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: _maxImageDim,
      maxHeight: _maxImageDim,
    );
    if (picked == null) return;
    await _enqueuePhoto(File(picked.path), picked.name);
  }

  /// M4 bulk: up to 100 photos/videos combined, max 10 videos per batch.
  Future<void> _pickPhotosBulk() async {
    final picked = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: _maxImageDim,
      maxHeight: _maxImageDim,
      limit: maxBulkMediaTotal,
    );
    if (picked.isEmpty) return;
    final queue = _queue;
    if (queue == null) {
      _showError('Attachments are not ready yet');
      return;
    }
    final files = <({File file, String name, String? mime})>[
      for (final x in picked) (file: File(x.path), name: x.name, mime: 'image/jpeg'),
    ];
    try {
      // One call preserves selection order via stable sort indexes.
      await queue.attachPhotos(files);
      _scrollToBottom();
    } on AttachmentLimitException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not add photos');
    }
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
    // M5: server-validated 10-minute policy (probe is authoritative).
    if (duration > 600) {
      _showError('Videos must be 10 minutes or shorter');
      return;
    }
    final ok = await _guardAttachment(file, _maxVideoBytes);
    if (ok == null || _queue == null) return;
    try {
      await _queue!.attachVideo(file: ok, fileName: picked.name, durationSeconds: duration);
      _scrollToBottom();
    } on AttachmentLimitException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not add video');
    }
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
    final ok = await _guardAttachment(file, _maxVoiceBytes);
    if (ok == null || _queue == null) return;
    try {
      await _queue!.attachVoice(
        file: ok,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        durationSeconds: (elapsed.inSeconds > 0 ? elapsed.inSeconds : 1).toDouble(),
      );
      _scrollToBottom();
    } catch (_) {
      _showError('Could not add voice message');
    }
  }

  Future<void> _pickDocument() async {
    final picked = await FilePicker.platform.pickFiles(withReadStream: false);
    if (picked == null || picked.files.isEmpty) return;
    final platformFile = picked.files.single;
    final path = platformFile.path;
    if (path == null) return;
    final ok = await _guardAttachment(File(path), _maxDocumentBytes);
    if (ok == null || _queue == null) return;
    try {
      await _queue!.attachDocument(
        file: ok,
        fileName: platformFile.name,
        mimeType: platformFile.extension != null
            ? _guessMime(platformFile.extension!) ?? 'application/octet-stream'
            : 'application/octet-stream',
      );
      _scrollToBottom();
    } catch (_) {
      _showError('Could not add document');
    }
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
              leading: const Icon(Icons.collections_outlined),
              title: const Text('Photos (up to 100)'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhotosBulk();
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

  String _mediaUrl(ChatMessage message) => resolveChatMediaUrl(message.mediaFile);

  Future<void> _openImageViewer(String url) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ChatImageViewerScreen(url: url, authToken: widget.session.token),
      ),
    );
  }

  Future<void> _handleMessageLongPress(ChatMessage message, bool isMine) async {
    final actions = availableMessageActions(
      message: message,
      isMine: isMine,
      canPost: widget.room.canPost,
    );
    if (actions.isEmpty) return;

    final action = await showChatMessageActionsSheet(context, actions: actions);
    if (!mounted || action == null) return;

    switch (action) {
      case ChatMessageAction.save:
        await _saveMessageMedia(message);
      case ChatMessageAction.edit:
        await _editMessage(message);
      case ChatMessageAction.delete:
        await _deleteMessage(message);
    }
  }

  Future<void> _saveMessageMedia(ChatMessage message) async {
    final url = _mediaUrl(message);
    if (url.isEmpty) {
      _showError('No media to save');
      return;
    }
    try {
      final result = await downloadChatMedia(
        url: url,
        authToken: widget.session.token,
        message: message,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${result.fileName}')),
      );
      if (message.isDocumentMessage) {
        await openDownloadedMedia(result);
      }
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not save media');
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed for everyone in the chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _chatApi.deleteMessage(token: widget.session.token, messageId: message.id);
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == message.id);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(isDeleted: true, content: null);
        }
      });
      await _persistMessages();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not delete message');
    }
  }

  Future<void> _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.content ?? '');
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Message'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next.isEmpty || next == message.content?.trim()) return;

    try {
      final updated = await _chatApi.updateMessage(
        token: widget.session.token,
        messageId: message.id,
        content: next,
      );
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == message.id);
        if (idx >= 0) _messages[idx] = updated;
      });
      await _persistMessages();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not update message');
    }
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

  /// M9: durable outbox (newest last). Acked server echoes arrive via
  /// socket and remove their pending tile through the queue listener.
  List<TextPending> get _textPendings => _textQueue?.pendings ?? const [];

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
    if (_messages.isEmpty && _textPendings.isEmpty) {
      return const Center(
        child: Text('No messages yet', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + _textPendings.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_loadingMore && index == _messages.length + _textPendings.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        // M9: durable outbox first (newest at the bottom, like sent messages).
        if (index < _textPendings.length) {
          final pending = _textPendings[_textPendings.length - 1 - index];
          return _PendingTextTile(
            pending: pending,
            onRetry: () => _retryPendingTexts(),
          );
        }
        final message = _messages[_messages.length - 1 - (index - _textPendings.length)];
        final isMine = message.sender.id == myUserId;
        return _MessageBubble(
          message: message,
          isMine: isMine,
          mediaUrl: _mediaUrl(message),
          authToken: widget.session.token,
          canPost: widget.room.canPost,
          onLongPress: () => _handleMessageLongPress(message, isMine),
          onImageTap: message.isImageMessage ? () => _openImageViewer(_mediaUrl(message)) : null,
        );
      },
    );
  }

  Widget _buildComposer() {
    final recording = _voiceRecorder.phase != VoiceRecorderPhase.idle;
    final queue = _queue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (queue != null && widget.room.canPost)
          ChatAttachmentTray(queue: queue, onSend: _sendAttachments),
        ChatComposerBar(
          controller: _composer,
          enabled: widget.room.canPost,
          sending: _textSending,
          isRecording: recording,
          isLocked: _voiceRecorder.phase == VoiceRecorderPhase.locked,
          recordElapsed: _voiceRecorder.elapsed,
          onAttach: _showAttachmentSheet,
          onCamera: () => _pickPhoto(ImageSource.camera),
          onSendText: _sendText,
          onRecordStart: _startVoiceRecording,
          onLockedSend: () => _finishVoiceRecording(send: true),
          onRecordCancel: () => _finishVoiceRecording(send: false),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.mediaUrl,
    required this.authToken,
    required this.canPost,
    this.onLongPress,
    this.onImageTap,
  });

  final ChatMessage message;
  final bool isMine;
  final String mediaUrl;
  final String authToken;
  final bool canPost;
  final VoidCallback? onLongPress;
  final VoidCallback? onImageTap;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('h:mm a').format(message.createdAt.toLocal());
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isMine ? AppColors.violet : AppColors.surface;
    final fg = isMine ? Colors.white : AppColors.textPrimary;
    final multi = message.displayAttachments.length > 1 && !message.isDeleted;
    final isImage = !multi && message.isImageMessage && mediaUrl.isNotEmpty && !message.isDeleted;
    final showCaption = message.isImageMessage && message.hasCaption;

    final bubble = Padding(
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
                if (multi)
                  ..._multiAttachmentWidgets(message, fg, isMine)
                else if (isImage)
                  ChatImageBubble(
                    url: mediaUrl,
                    authToken: authToken,
                    onTap: onImageTap,
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
                if (showCaption && !multi)
                  Padding(
                    padding: EdgeInsets.fromLTRB(isImage ? 10 : 0, isImage ? 6 : 4, isImage ? 10 : 0, 0),
                    child: Text(
                      message.content!.trim(),
                      style: TextStyle(color: fg, fontSize: 15, height: 1.35),
                    ),
                  ),
                if (multi && message.hasCaption)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
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

    if (onLongPress == null) return bubble;
    return GestureDetector(onLongPress: onLongPress, behavior: HitTestBehavior.opaque, child: bubble);
  }

  /// Renders every attachment in selection order, reusing the existing
  /// single-media bubble widgets (no new rendering stack).
  List<Widget> _multiAttachmentWidgets(ChatMessage message, Color fg, bool isMine) {
    final widgets = <Widget>[];
    for (final media in message.displayAttachments) {
      final url = resolveChatMediaUrl(media);
      if (url.isEmpty) continue;
      if (media.isImage) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ChatImageBubble(url: url, authToken: authToken, onTap: onImageTap),
        ));
      } else if (media.isAudio) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ChatVoiceBubble(
            url: url,
            authToken: authToken,
            foregroundColor: fg,
            accentColor: isMine ? Colors.white : AppColors.violet,
          ),
        ));
      } else if (media.isVideo) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ChatVideoBubble(url: url, authToken: authToken),
        ));
      } else {
        final segment = Uri.tryParse(url)?.pathSegments.lastWhere(
              (s) => s.isNotEmpty,
              orElse: () => '',
            ) ??
            '';
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ChatDocumentBubble(
            url: url,
            authToken: authToken,
            fileName: segment.isNotEmpty ? segment : 'Document',
            foregroundColor: fg,
            accentColor: isMine ? Colors.white : AppColors.violet,
          ),
        ));
      }
    }
    return widgets;
  }
}

/// M9: durable outbox tile for a text intent not yet acknowledged.
/// Dimmed bubble with state icon; failed/uncertain tiles retry on tap
/// with the SAME clientMessageId (server dedupes — no duplicates).
class _PendingTextTile extends StatelessWidget {
  const _PendingTextTile({required this.pending, required this.onRetry});

  final TextPending pending;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = pending.state == SendIntentState.failed ||
        pending.state == SendIntentState.uncertain;
    final icon = pending.state == SendIntentState.sending
        ? Icons.schedule
        : failed
            ? Icons.error_outline
            : Icons.check;
    final label = pending.state == SendIntentState.sending
        ? 'Sending…'
        : failed
            ? 'Not sent — tap to retry'
            : 'Sent';
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: failed ? onRetry : null,
        child: Opacity(
          opacity: failed ? 0.75 : 0.6,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.violet.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pending.text, style: const TextStyle(color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
