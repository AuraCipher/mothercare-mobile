import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'api_exception.dart';

class AuthenticatedClient {
  AuthenticatedClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> getJson(
    String path, {
    required String token,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final res = await _client
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 25));

    return _decode(res);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required String token,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
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
        .timeout(const Duration(seconds: 25));

    return _decode(res);
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
}
