import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../core/api/http_client_factory.dart';
import '../models/auth_models.dart';

class AuthApiException implements Exception {
  AuthApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthApi {
  AuthApi({http.Client? client, String? baseUrl})
      : _client = HttpClientFactory.create(client: client),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<LoginResponse> login({
    required String identifier,
    required String password,
    bool rememberMe = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/login');
    final res = await _client
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'identifier': identifier,
            'password': password,
            'rememberMe': rememberMe,
          }),
        )
        .timeout(const Duration(seconds: 20));

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw AuthApiException(
        res.statusCode >= 500
            ? 'Server error. Try again later.'
            : 'Unexpected response from server',
        statusCode: res.statusCode,
      );
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final parsed = LoginResponse.fromJson(body);
      if (!parsed.success || parsed.token.isEmpty) {
        throw AuthApiException(parsed.message ?? 'Login failed');
      }
      return parsed;
    }

    throw AuthApiException(
      body['message'] as String? ?? 'Login failed (${res.statusCode})',
      statusCode: res.statusCode,
    );
  }
}
