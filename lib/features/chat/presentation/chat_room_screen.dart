import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../config/app_config.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chat_api.dart';
import '../data/chat_socket_service.dart';
import '../data/upload_api.dart';
import '../../../core/widgets/universal_header.dart';
import '../models/chat_models.dart';

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
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _composer = TextEditingController();
  final _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _recording = false;
  String? _error;
  String? _cursor;
  bool _hasMore = true;
  StreamSubscription<ChatMessage>? _messageSub;

  @override
  void initState() {
    super.initState();
    widget.socket.joinRoom(widget.room.id);
    widget.socket.markRead(roomId: widget.room.id);
    _messageSub = widget.socket.onMessage.listen(_onSocketMessage);
    _scrollController.addListener(_onScroll);
    _loadMessages();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _recorder.dispose();
    _scrollController.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onSocketMessage(ChatMessage message) {
    if (message.roomId != widget.room.id) return;
    if (_messages.any((m) => m.id == message.id)) return;
    setState(() => _messages.add(message));
    widget.socket.markRead(roomId: widget.room.id, messageId: message.id);
    _scrollToBottom();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || !_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 80) {
      _loadMore();
    }
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
        _hasMore = messages.length >= 40;
        _cursor = messages.isNotEmpty ? messages.first.createdAt.toUtc().toIso8601String() : null;
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
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

  Future<void> _sendMedia({
    required File file,
    required String fileName,
    required String purpose,
    required String messageType,
  }) async {
    final ayId = widget.academicYearId;
    if (ayId == null || ayId.isEmpty) {
      _showError('Academic year is required for attachments');
      return;
    }
    if (_sending || !widget.room.canPost) return;

    setState(() => _sending = true);
    try {
      final uploaded = await _uploadApi.uploadChatFile(
        token: widget.session.token,
        file: file,
        fileName: fileName,
        roomId: widget.room.id,
        academicYearId: ayId,
        purpose: purpose,
      );
      widget.socket.sendMessage(
        roomId: widget.room.id,
        type: messageType,
        mediaFileId: uploaded.id,
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Failed to upload attachment');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
    );
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    await _sendMedia(
      file: file,
      fileName: picked.name,
      purpose: 'video',
      messageType: 'video',
    );
  }

  Future<void> _toggleVoiceRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path == null) return;
      final file = File(path);
      await _sendMedia(
        file: file,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        purpose: 'voice_note',
        messageType: 'voice_note',
      );
      return;
    }

    if (!await _recorder.hasPermission()) {
      _showError('Microphone permission is required for voice notes');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() => _recording = true);
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
              leading: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none_rounded),
              title: Text(_recording ? 'Stop & send voice note' : 'Voice note'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleVoiceRecording();
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
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          UniversalHeader(
            title: widget.room.name,
            showBack: true,
          ),
          if (_recording)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.error.withValues(alpha: 0.1),
              child: const Row(
                children: [
                  Icon(Icons.fiber_manual_record, color: AppColors.error, size: 12),
                  SizedBox(width: 8),
                  Text('Recording voice note…', style: TextStyle(fontSize: 12, color: AppColors.error)),
                ],
              ),
            ),
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
    if (_messages.isEmpty) {
      return const Center(
        child: Text('No messages yet', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_loadingMore && index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final message = _messages[_messages.length - 1 - index];
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            IconButton(
              onPressed: _sending ? null : _showAttachmentSheet,
              icon: const Icon(Icons.attach_file_rounded, color: AppColors.violet),
            ),
            Expanded(
              child: TextField(
                controller: _composer,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: 'Message',
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _sendText,
              style: IconButton.styleFrom(backgroundColor: AppColors.violet, foregroundColor: Colors.white),
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                if (message.mediaFile?.isImage == true && mediaUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      mediaUrl,
                      headers: {'Authorization': 'Bearer $authToken', 'Accept': 'image/*'},
                      width: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Text(message.displayText, style: TextStyle(color: fg)),
                    ),
                  )
                else if (message.mediaFile?.isVideo == true || message.type == 'video')
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_rounded, color: fg, size: 20),
                      const SizedBox(width: 8),
                      Text('Video', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                    ],
                  )
                else if (message.mediaFile?.isAudio == true || message.type == 'voice_note' || message.type == 'audio')
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_rounded, color: fg, size: 20),
                      const SizedBox(width: 8),
                      Text('Voice message', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                    ],
                  ),
                if (message.displayText.isNotEmpty &&
                    !(message.mediaFile?.isImage == true && message.content?.trim().isEmpty != false))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(message.displayText, style: TextStyle(color: fg, fontSize: 15, height: 1.35)),
                  ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(fontSize: 10, color: isMine ? Colors.white70 : AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
