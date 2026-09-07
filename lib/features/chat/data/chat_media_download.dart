import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/chat_models.dart';

class ChatMediaDownloadResult {
  const ChatMediaDownloadResult({required this.path, required this.fileName});

  final String path;
  final String fileName;
}

Future<ChatMediaDownloadResult> downloadChatMedia({
  required String url,
  required String authToken,
  required ChatMessage message,
}) async {
  final res = await http.get(
    Uri.parse(url),
    headers: {
      'Authorization': 'Bearer $authToken',
      'Accept': '*/*',
    },
  ).timeout(const Duration(seconds: 30));
  if (res.statusCode < 200 || res.statusCode >= 300 || res.bodyBytes.isEmpty) {
    throw Exception('Download failed (${res.statusCode})');
  }

  final fileName = _fileNameForMessage(message);
  final dir = await getApplicationDocumentsDirectory();
  final downloadsDir = Directory(p.join(dir.path, 'chat_downloads'));
  if (!await downloadsDir.exists()) {
    await downloadsDir.create(recursive: true);
  }
  final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
  final file = File(p.join(downloadsDir.path, safeName));
  await file.writeAsBytes(res.bodyBytes, flush: true);
  return ChatMediaDownloadResult(path: file.path, fileName: safeName);
}

Future<void> openDownloadedMedia(ChatMediaDownloadResult result) async {
  await OpenFilex.open(result.path);
}

String _fileNameForMessage(ChatMessage message) {
  if (message.isDocumentMessage) return message.documentFileName;
  final media = message.mediaFile;
  if (media == null) return 'chat_media';
  if (message.isImageMessage) {
    final ext = _extFromMime(media.mimeType, fallback: 'jpg');
    return 'photo_${message.id}.$ext';
  }
  if (media.isVideo || message.type == 'video') {
    final ext = _extFromMime(media.mimeType, fallback: 'mp4');
    return 'video_${message.id}.$ext';
  }
  if (media.isAudio || message.type == 'voice_note') {
    final ext = _extFromMime(media.mimeType, fallback: 'm4a');
    return 'voice_${message.id}.$ext';
  }
  return 'file_${message.id}';
}

String _extFromMime(String mime, {required String fallback}) {
  final parts = mime.split('/');
  if (parts.length == 2 && parts[1].isNotEmpty && !parts[1].contains('+')) {
    return parts[1];
  }
  return fallback;
}
