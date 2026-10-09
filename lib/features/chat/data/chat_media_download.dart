import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/media/media_store.dart';
import '../models/chat_models.dart';

class ChatMediaDownloadResult {
  const ChatMediaDownloadResult({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  /// Local file path — a temp-cache file until it is persisted.
  final String path;

  /// Best-effort real file name — the server's original upload name when
  /// available (Content-Disposition), otherwise a synthesized name whose
  /// extension matches the actual bytes.
  final String fileName;

  /// MIME used when the file is handed to the system media store; derived
  /// from the file name's extension first, then magic bytes.
  final String mimeType;
}

/// One successfully saved file in a batch.
class ChatMediaSavedFile {
  const ChatMediaSavedFile({
    required this.fileName,
    required this.path,
    required this.isPublic,
  });

  final String fileName;

  /// Final location: content URI (public gallery/Downloads) or app-private
  /// path (documents kept in `chat_downloads`).
  final String path;

  /// True when saved through the system media store (gallery/Downloads).
  final bool isPublic;
}

/// Outcome of a multi-file save (Save all / Save selected / single save).
class ChatMediaSaveReport {
  const ChatMediaSaveReport({required this.saved, required this.failures});

  final List<ChatMediaSavedFile> saved;
  final List<String> failures;

  List<String> get savedNames => [for (final f in saved) f.fileName];
  int get savedCount => saved.length;
  int get failedCount => failures.length;
  bool get allSaved => failures.isEmpty && saved.isNotEmpty;
}

/// True when a file belongs in the public gallery/Downloads collections
/// (MediaStore / Photos) rather than the app-private documents dir.
bool isPublicGalleryMime(String mime) =>
    mime.startsWith('image/') || mime.startsWith('video/') || mime.startsWith('audio/');

/// Downloads chat media into the temp cache and derives the best file name.
///
/// Naming: prefers the original uploaded file name from the response's
/// `Content-Disposition` header (the backend always sends
/// `filename*=UTF-8''<original>` on `GET /api/uploads/:id`), then the
/// document title, then a synthesized name derived from magic-byte sniffing
/// of the payload — never from the declared MIME alone.
Future<ChatMediaDownloadResult> downloadChatMedia({
  required String url,
  required String authToken,
  ChatMessage? message,
  ChatMessageMedia? media,
  http.Client? client,
}) async {
  final ownedClient = client ?? http.Client();
  late final http.Response res;
  try {
    res = await ownedClient
        .get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $authToken',
            'Accept': '*/*',
          },
        )
        .timeout(const Duration(seconds: 30));
  } finally {
    if (client == null) ownedClient.close();
  }
  if (res.statusCode < 200 || res.statusCode >= 300 || res.bodyBytes.isEmpty) {
    throw Exception('Download failed (${res.statusCode})');
  }

  final fileName = resolveDownloadFileName(
    contentDisposition: res.headers['content-disposition'],
    bytes: res.bodyBytes,
    message: message,
    media: media,
    declaredMime: res.headers['content-type'],
  );
  final mimeType = mediaStoreMimeFor(
    fileName: fileName,
    bytes: res.bodyBytes,
    declaredMime: res.headers['content-type'] ?? media?.mimeType,
  );

  final dir = await getTemporaryDirectory();
  final sinkDir = Directory(p.join(dir.path, 'chat_out'));
  if (!await sinkDir.exists()) {
    await sinkDir.create(recursive: true);
  }
  final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
  final file = File(p.join(sinkDir.path, safeName));
  await file.writeAsBytes(res.bodyBytes, flush: true);
  return ChatMediaDownloadResult(
    path: file.path,
    fileName: safeName,
    mimeType: mimeType,
  );
}

/// Hands a downloaded file to the system gallery/Downloads through the
/// `mcs.media_store` channel and removes the temp copy.
Future<String> saveToSystemGallery(ChatMediaDownloadResult result) async {
  try {
    return await MediaStore.save(
      path: result.path,
      mimeType: result.mimeType,
      fileName: result.fileName,
    );
  } finally {
    await deleteQuietly(result.path);
  }
}

/// Moves a non-public file (documents etc.) into the app-private
/// `chat_downloads` dir — the legacy location that stays on device and can be
/// opened afterwards. Temp copy is always cleaned up.
Future<ChatMediaSavedFile> keepInPrivateDownloads(ChatMediaDownloadResult result) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory(p.join(dir.path, 'chat_downloads'));
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    final dest = await _uniqueFile(downloadsDir, result.fileName);
    await File(result.path).copy(dest.path);
    return ChatMediaSavedFile(
      fileName: p.basename(dest.path),
      path: dest.path,
      isPublic: false,
    );
  } finally {
    await deleteQuietly(result.path);
  }
}

/// Saves a list of media URLs: images/videos/voice notes go to the public
/// gallery/Downloads via the media-store channel; anything else lands in the
/// app-private `chat_downloads` dir (documents — openable by the caller).
Future<ChatMediaSaveReport> saveChatMediaUrls({
  required List<String> urls,
  required String authToken,
  ChatMessage? message,
  void Function(int done, int total)? onProgress,
  http.Client? client,
}) async {
  final saved = <ChatMediaSavedFile>[];
  final failures = <String>[];
  var done = 0;
  for (final url in urls) {
    if (url.isEmpty) {
      failures.add(url);
      done++;
      onProgress?.call(done, urls.length);
      continue;
    }
    try {
      final result = await downloadChatMedia(
        url: url,
        authToken: authToken,
        message: message,
        client: client,
      );
      if (isPublicGalleryMime(result.mimeType)) {
        final uri = await saveToSystemGallery(result);
        saved.add(ChatMediaSavedFile(
          fileName: result.fileName,
          path: uri,
          isPublic: true,
        ));
      } else {
        saved.add(await keepInPrivateDownloads(result));
      }
    } catch (_) {
      failures.add(url);
    }
    done++;
    onProgress?.call(done, urls.length);
  }
  return ChatMediaSaveReport(saved: saved, failures: failures);
}

Future<void> openDownloadedMedia(ChatMediaSavedFile saved) async {
  await OpenFilex.open(saved.path);
}

Future<void> deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

// ─── File naming ────────────────────────────────────────────────────────────

/// Best-effort real file name for a download.
///
/// 1. `Content-Disposition` filename (RFC 5987 `filename*=` or plain
///    `filename=`) — the backend echoes the uploader's original name.
/// 2. The message document title (documents without a disposition header).
/// 3. A synthesized name whose extension comes from magic-byte sniffing of
///    the actual payload, falling back to a corrected MIME→ext map.
String resolveDownloadFileName({
  String? contentDisposition,
  required Uint8List bytes,
  ChatMessage? message,
  ChatMessageMedia? media,
  String? declaredMime,
}) {
  final fromHeader = parseContentDispositionFileName(contentDisposition);
  if (fromHeader != null && fromHeader.isNotEmpty) return fromHeader;

  if (message != null && message.isDocumentMessage) {
    final title = message.documentFileName;
    if (title.isNotEmpty && title != 'Document') return title;
  }

  final sniffedMime = sniffMime(bytes);
  final ext = extensionForMime(sniffedMime ?? '') ??
      extensionForMime(media?.mimeType ?? '') ??
      extensionForMime(declaredMime ?? '') ??
      'bin';
  final id = _shortId(media?.id ?? message?.id ?? '');
  if (sniffedMime == null || sniffedMime.startsWith('image/')) {
    return id.isEmpty ? 'photo.$ext' : 'photo_$id.$ext';
  }
  if (sniffedMime.startsWith('video/')) {
    return id.isEmpty ? 'video.$ext' : 'video_$id.$ext';
  }
  if (sniffedMime.startsWith('audio/')) {
    return id.isEmpty ? 'voice.$ext' : 'voice_$id.$ext';
  }
  return id.isEmpty ? 'file.$ext' : 'file_$id.$ext';
}

String _shortId(String id) =>
    id.length <= 8 ? id : id.substring(0, 8).replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');

Future<File> _uniqueFile(Directory dir, String fileName) async {
  var candidate = File(p.join(dir.path, fileName));
  if (!await candidate.exists()) return candidate;
  final ext = p.extension(fileName); // includes dot
  final stem = p.basenameWithoutExtension(fileName);
  var i = 1;
  while (true) {
    final next = File(p.join(dir.path, '$stem ($i)$ext'));
    if (!await next.exists()) return next;
    i++;
  }
}

/// Parses a `Content-Disposition` header value.
/// Supports RFC 5987 `filename*=UTF-8''name.ext` and plain `filename="name"`.
String? parseContentDispositionFileName(String? header) {
  if (header == null || header.trim().isEmpty) return null;

  final starMatch = RegExp(
    r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)",
    caseSensitive: false,
  ).firstMatch(header);
  if (starMatch != null) {
    final encoded = starMatch.group(2)!.trim();
    try {
      final decoded = Uri.decodeComponent(encoded);
      if (decoded.isNotEmpty) return decoded;
    } catch (_) {/* fall through */}
  }

  final plainMatch = RegExp(
    r'filename\s*=\s*"([^"]+)"',
    caseSensitive: false,
  ).firstMatch(header) ??
      RegExp(
        r'filename\s*=\s*([^;\s]+)',
        caseSensitive: false,
      ).firstMatch(header);
  final plain = plainMatch?.group(1)?.trim();
  if (plain != null && plain.isNotEmpty) return plain;
  return null;
}

/// Magic-byte MIME sniff covering the payload types chat can carry.
/// Returns `null` when nothing matches.
String? sniffMime(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  final b = bytes;

  bool startsWith(List<int> sig, [int offset = 0]) {
    if (b.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[offset + i] != sig[i]) return false;
    }
    return true;
  }

  // Images
  if (startsWith([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (startsWith([0x47, 0x49, 0x46, 0x38])) return 'image/gif'; // GIF8
  if (startsWith([0x42, 0x4D])) return 'image/bmp';
  if (startsWith([0x49, 0x49, 0x2A, 0x00]) || startsWith([0x4D, 0x4D, 0x00, 0x2A])) {
    return 'image/tiff';
  }

  // RIFF containers: WEBP / WAVE / AVI
  if (startsWith([0x52, 0x49, 0x46, 0x46]) && b.length >= 12) {
    final sub = String.fromCharCodes(b.sublist(8, 12));
    if (sub == 'WEBP') return 'image/webp';
    if (sub == 'WAVE') return 'audio/wav';
    if (sub == 'AVI ') return 'video/x-msvideo';
  }

  // ISO-BMFF: mp4 / m4a / m4b / mov / heic — check the ftyp brand.
  if (b.length >= 12 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') {
    final brand = String.fromCharCodes(b.sublist(8, 12));
    switch (brand) {
      case 'M4A ':
      case 'M4B ':
        return 'audio/mp4';
      case 'qt  ':
        return 'video/quicktime';
      default:
        switch (brand.trim()) {
          case 'heic':
          case 'heix':
          case 'hevc':
          case 'mif1':
          case 'msf1':
            return 'image/heic';
          default:
            return 'video/mp4';
        }
    }
  }

  // Audio
  if (startsWith([0x4F, 0x67, 0x67, 0x53])) return 'audio/ogg'; // OggS
  if (startsWith([0x49, 0x44, 0x33])) return 'audio/mpeg'; // ID3
  if (b.length >= 2 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) {
    // MPEG frame sync (mp3 without an ID3 tag; JPEG 0xFFD8 already matched).
    return 'audio/mpeg';
  }
  if (startsWith([0x66, 0x4C, 0x61, 0x43])) return 'audio/flac'; // fLaC

  // Documents / archives
  if (startsWith([0x25, 0x50, 0x44, 0x46])) return 'application/pdf'; // %PDF
  if (startsWith([0x50, 0x4B, 0x03, 0x04]) ||
      startsWith([0x50, 0x4B, 0x05, 0x06]) ||
      startsWith([0x50, 0x4B, 0x07, 0x08])) {
    return 'application/zip'; // docx/xlsx/pptx/epub share the zip envelope
  }
  if (startsWith([0x7B, 0x5C, 0x72, 0x74, 0x66])) return 'application/rtf'; // {\rtf
  if (_looksLikeText(b)) {
    final text = String.fromCharCodes(b.take(512));
    if (text.contains('<svg')) return 'image/svg+xml';
    if (text.startsWith('{"') || text.startsWith('[')) return 'application/json';
    if (text.contains('<')) return 'text/html';
    return 'text/plain';
  }
  return null;
}

bool _looksLikeText(Uint8List b) {
  final limit = b.length < 512 ? b.length : 512;
  for (var i = 0; i < limit; i++) {
    final c = b[i];
    if (c == 0x00) return false;
    if (c < 0x09 || (c > 0x0D && c < 0x20)) return false;
  }
  return limit > 0;
}

/// Canonical extension for a MIME type (`image/jpeg` → `jpg`, never `jpeg`).
String? extensionForMime(String mime) {
  const direct = <String, String>{
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/bmp': 'bmp',
    'image/tiff': 'tiff',
    'image/heic': 'heic',
    'image/heif': 'heif',
    'image/svg+xml': 'svg',
    'image/x-icon': 'ico',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'video/3gpp': '3gp',
    'video/x-msvideo': 'avi',
    'audio/mp4': 'm4a',
    'audio/mpeg': 'mp3',
    'audio/aac': 'aac',
    'audio/ogg': 'ogg',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/flac': 'flac',
    'application/pdf': 'pdf',
    'application/zip': 'zip',
    'application/json': 'json',
    'application/rtf': 'rtf',
    'text/plain': 'txt',
    'text/html': 'html',
    'application/octet-stream': 'bin',
  };
  final normalized = mime.toLowerCase().trim();
  if (direct.containsKey(normalized)) return direct[normalized];
  final parts = normalized.split('/');
  if (parts.length == 2 && parts[1].isNotEmpty && !parts[1].contains('+')) {
    return parts[1];
  }
  return null;
}

/// MIME handed to the media store for a file name: derived from the name's
/// extension first (so the saved entry is labelled exactly like the visible
/// file), then magic bytes, then whatever the server declared.
String mediaStoreMimeFor({
  required String fileName,
  Uint8List? bytes,
  String? declaredMime,
}) {
  final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
  if (ext.isNotEmpty) {
    const extMime = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'tiff': 'image/tiff',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'svg': 'image/svg+xml',
      'ico': 'image/x-icon',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      '3gp': 'video/3gpp',
      'avi': 'video/x-msvideo',
      'm4a': 'audio/mp4',
      'm4b': 'audio/mp4',
      'mp3': 'audio/mpeg',
      'aac': 'audio/aac',
      'ogg': 'audio/ogg',
      'wav': 'audio/wav',
      'flac': 'audio/flac',
      'pdf': 'application/pdf',
      'zip': 'application/zip',
      'json': 'application/json',
      'rtf': 'application/rtf',
      'txt': 'text/plain',
      'html': 'text/html',
    };
    final byExt = extMime[ext];
    if (byExt != null) return byExt;
  }
  if (bytes != null) {
    final sniffed = sniffMime(bytes);
    if (sniffed != null) return sniffed;
  }
  final declared = declaredMime?.split(';').first.trim();
  if (declared != null && declared.isNotEmpty && declared != 'application/octet-stream') {
    return declared;
  }
  return 'application/octet-stream';
}
