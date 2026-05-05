import 'dart:convert';

import 'package:logis_agent/models/agent.dart';

class AuthSession {
  final Agent? agent;
  final Map<String, dynamic>? mission;
  final Map<String, dynamic>? settings;

  const AuthSession({
    required this.agent,
    required this.mission,
    required this.settings,
  });

  Map<String, dynamic> toJson() {
    return {
      'agent': agent?.toJson(),
      'mission': mission,
      'settings': settings,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final agentJson = json['agent'];
    Agent? agent;
    if (agentJson is Map<String, dynamic>) {
      agent = Agent.fromJson(agentJson);
    }

    final mission = json['mission'];
    final settings = json['settings'];

    return AuthSession(
      agent: agent,
      mission: mission is Map<String, dynamic> ? mission : null,
      settings: settings is Map<String, dynamic> ? settings : null,
    );
  }

  factory AuthSession.fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid session json');
    }
    return AuthSession.fromJson(decoded);
  }
}
