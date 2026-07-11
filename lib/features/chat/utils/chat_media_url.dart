import '../../../config/app_config.dart';
import '../models/chat_models.dart';

/// Resolves chat media URLs using the device API base — ignores stored server host.
String resolveChatMediaUrl(ChatMessageMedia? media) {
  if (media == null) return '';
  if (media.id.isNotEmpty) {
    return '${AppConfig.apiBaseUrl}/api/uploads/${media.id}';
  }
  return resolveChatMediaUrlFromParts(publicUrl: media.url);
}

String resolveChatMediaUrlFromParts({String? publicUrl, String? fileId}) {
  if (fileId != null && fileId.isNotEmpty) {
    return '${AppConfig.apiBaseUrl}/api/uploads/$fileId';
  }
  final url = publicUrl?.trim() ?? '';
  if (url.isEmpty) return '';
  if (url.startsWith('/')) {
    return '${AppConfig.apiBaseUrl}$url';
  }
  final uri = Uri.tryParse(url);
  if (uri != null && uri.path.startsWith('/api/uploads/')) {
    return '${AppConfig.apiBaseUrl}${uri.path}';
  }
  if (url.startsWith('http')) return url;
  return '${AppConfig.apiBaseUrl}/$url';
}
