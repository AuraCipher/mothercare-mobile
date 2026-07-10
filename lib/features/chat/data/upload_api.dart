import 'dart:io';

import '../../../core/api/authenticated_client.dart';

class UploadApi {
  UploadApi({AuthenticatedClient? client}) : _client = client ?? AuthenticatedClient();

  final AuthenticatedClient _client;

  Future<UploadedFile> uploadChatFile({
    required String token,
    required File file,
    required String fileName,
    required String roomId,
    required String academicYearId,
    required String purpose,
  }) async {
    final body = await _client.uploadMultipart(
      '/api/upload',
      token: token,
      file: file,
      fileName: fileName,
      fields: {
        'purpose': purpose,
        'entityType': 'chat',
        'roomId': roomId,
        'academicYearId': academicYearId,
      },
    );
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return UploadedFile.fromJson(data);
  }
}

class UploadedFile {
  const UploadedFile({
    required this.id,
    required this.url,
    required this.mimeType,
    required this.purpose,
  });

  final String id;
  final String url;
  final String mimeType;
  final String purpose;

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      purpose: json['purpose'] as String? ?? 'chat',
    );
  }
}
