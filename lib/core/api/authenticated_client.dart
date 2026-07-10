import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'api_exception.dart';
import 'http_client_factory.dart';
import 'progress_file_stream.dart';

class AuthenticatedClient {
  AuthenticatedClient({http.Client? client, String? baseUrl})
      : _client = HttpClientFactory.create(client: client),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> getJson(
    String path, {
    required String token,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    try {
      final res = await _client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      return _decode(res);
    } on TimeoutException {
      throw ApiException('No internet connection. Check your network.');
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    try {
      final res = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      return _decode(res);
    } on TimeoutException {
      throw ApiException('No internet connection. Check your network.');
    }
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    required String token,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final request = http.Request('DELETE', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'application/json';
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final streamed = await _client.send(request).timeout(const Duration(seconds: 10));
      final res = await http.Response.fromStream(streamed);
      return _decode(res);
    } on TimeoutException {
      throw ApiException('No internet connection. Check your network.');
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        res.statusCode >= 500 ? 'Server error. Try again later.' : 'Unexpected response from server',
        statusCode: res.statusCode,
      );
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (body['success'] == false) {
        throw ApiException(body['message'] as String? ?? 'Request failed', statusCode: res.statusCode);
      }
      return body;
    }

    throw ApiException(
      body['message'] as String? ?? 'Request failed (${res.statusCode})',
      statusCode: res.statusCode,
    );
  }

  Future<Map<String, dynamic>> uploadMultipart(
    String path, {
    required String token,
    required File file,
    required String fileName,
    required Map<String, String> fields,
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
      request.fields.addAll(fields);

      final total = await file.length();
      final byteStream = onProgress == null
          ? http.ByteStream(file.openRead())
          : http.ByteStream(fileUploadStream(file, onProgress));

      request.files.add(http.MultipartFile(
        'file',
        byteStream,
        total,
        filename: fileName,
      ));

      final streamed = await request.send().timeout(const Duration(minutes: 10));
      final res = await http.Response.fromStream(streamed);
      return _decode(res);
    } on TimeoutException {
      throw ApiException('Upload timed out. Check your network.');
    }
  }
}
