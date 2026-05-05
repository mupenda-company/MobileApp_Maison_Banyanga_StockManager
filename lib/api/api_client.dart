import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Object? body;

  const ApiException({
    required this.message,
    this.statusCode,
    this.body,
  });

  @override
  String toString() => 'ApiException(statusCode: $statusCode, message: $message)';
}

class ApiClient {
  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final http.Client _client;

  ApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Uri _uri(String path) {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Future<Map<String, String>> _headers({Map<String, String>? extra}) async {
    final token = await tokenProvider();

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    if (extra != null) {
      headers.addAll(extra);
    }

    return headers;
  }

  Future<dynamic> getJson(String path) async {
    final response = await _client.get(
      _uri(path),
      headers: await _headers(),
    );

    return _decodeOrThrow(response);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      _uri(path),
      headers: await _headers(),
      body: jsonEncode(body),
    );

    return _decodeOrThrow(response);
  }

  dynamic _decodeOrThrow(http.Response response) {
    final statusOk = response.statusCode >= 200 && response.statusCode < 300;

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }

    if (!statusOk) {
      String message = 'Erreur API (${response.statusCode})';
      if (decoded is Map<String, dynamic>) {
        final maybeMessage = (decoded['message'] ?? decoded['error'])?.toString();
        if (maybeMessage != null && maybeMessage.isNotEmpty) {
          message = maybeMessage;
        }
      }

      throw ApiException(message: message, statusCode: response.statusCode, body: decoded);
    }

    return decoded;
  }
}
