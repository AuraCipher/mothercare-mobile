import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config/app_config.dart';
import 'package:mobile/features/chat/models/chat_models.dart';
import 'package:mobile/features/chat/utils/chat_media_url.dart';

void main() {
  test('resolveChatMediaUrl prefers file id over stored host', () {
    const media = ChatMessageMedia(
      id: 'file-123',
      mimeType: 'image/jpeg',
      url: 'http://10.0.2.2:5000/api/uploads/file-123',
    );

    expect(
      resolveChatMediaUrl(media),
      '${AppConfig.apiBaseUrl}/api/uploads/file-123',
    );
  });

  test('resolveChatMediaUrlFromParts rewrites absolute upload path', () {
    expect(
      resolveChatMediaUrlFromParts(publicUrl: 'http://localhost:5000/api/uploads/abc'),
      '${AppConfig.apiBaseUrl}/api/uploads/abc',
    );
    expect(
      resolveChatMediaUrlFromParts(publicUrl: '/api/uploads/abc'),
      '${AppConfig.apiBaseUrl}/api/uploads/abc',
    );
  });
}
