class Agent {
  final String? id;
  final String? username;
  final String? fullName;

  const Agent({
    required this.id,
    required this.username,
    required this.fullName,
  });

  factory Agent.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? json['_id']?.toString();
    final username = (json['username'] ?? json['email'] ?? json['login'])?.toString();

    final nom = json['nom']?.toString();
    final prenom = json['prenom']?.toString();
    final fromNomPrenom = ((prenom ?? '').trim().isNotEmpty || (nom ?? '').trim().isNotEmpty)
        ? ('${(prenom ?? '').trim()} ${(nom ?? '').trim()}'.trim())
        : null;

    final fullName = (json['full_name'] ?? json['fullName'] ?? json['name'] ?? fromNomPrenom)?.toString();

    return Agent(
      id: id,
      username: username,
      fullName: fullName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'fullName': fullName,
    };
  }
}
