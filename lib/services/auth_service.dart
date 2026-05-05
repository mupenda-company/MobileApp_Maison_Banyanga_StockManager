import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/models/agent.dart';
import 'package:logis_agent/models/auth_session.dart';
import 'package:logis_agent/theme/app_theme_controller.dart';

class AuthService {
  static final AuthService instance = AuthService._();

  AuthService._();

  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'auth_session';

  AuthSession? _session;

  AuthSession? get session => _session;

  Future<AuthSession?> restoreSession() async {
    final value = await _storage.read(key: _sessionKey);
    if (value == null || value.isEmpty) {
      _session = null;
      return null;
    }

    try {
      _session = AuthSession.fromJsonString(value);
      AppThemeController.instance.updateFromSettings(_session?.settings);
      return _session;
    } catch (_) {
      _session = null;
      await _storage.delete(key: _sessionKey);
      return null;
    }
  }

  Future<AuthSession> login({required String username, required String password}) async {
    if (AppConfig.apiBaseUrl.isEmpty) {
      throw const FormatException('API_BASE_URL non configuré');
    }

    final uri = Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.loginPath}');

    final response = await http.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Identifiants invalides';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final maybeMessage = (decoded['message'] ?? decoded['error'])?.toString();
          if (maybeMessage != null && maybeMessage.isNotEmpty) {
            message = maybeMessage;
          }
        }
      } catch (_) {}

      throw Exception(message);
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Réponse login invalide');
    }

    final data = decoded['data'];
    final payload = data is Map<String, dynamic> ? data : decoded;

    final userJson = payload['user'] ?? payload['agent'];
    Agent? agent;
    if (userJson is Map<String, dynamic>) {
      agent = Agent.fromJson(userJson);
    }

    final mission = payload['mission'];
    final settings = payload['settings'];

    _session = AuthSession(
      agent: agent,
      mission: mission is Map<String, dynamic> ? mission : null,
      settings: settings is Map<String, dynamic> ? settings : null,
    );

    AppThemeController.instance.updateFromSettings(_session?.settings);
    await _storage.write(key: _sessionKey, value: _session!.toJsonString());

    return _session!;
  }

  Future<void> logout() async {
    _session = null;
    await _storage.delete(key: _sessionKey);
  }

  Future<String?> getAccessToken() async {
    return null;
  }
}
