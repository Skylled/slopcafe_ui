class AgentListing {
  final String id;
  final String name;
  final DateTime createdAt;
  final int activeKeys;
  final int totalKeys;
  final int liveDocs;

  AgentListing({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.activeKeys,
    required this.totalKeys,
    required this.liveDocs,
  });

  factory AgentListing.fromJson(Map<String, dynamic> json) {
    return AgentListing(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      activeKeys: json['active_keys'] as int? ?? 0,
      totalKeys: json['total_keys'] as int? ?? 0,
      liveDocs: json['live_docs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'active_keys': activeKeys,
      'total_keys': totalKeys,
      'live_docs': liveDocs,
    };
  }
}

class AgentKey {
  final String id;
  final String keyPrefix;
  final DateTime createdAt;
  final DateTime? revokedAt;

  AgentKey({
    required this.id,
    required this.keyPrefix,
    required this.createdAt,
    this.revokedAt,
  });

  bool get isRevoked => revokedAt != null;

  factory AgentKey.fromJson(Map<String, dynamic> json) {
    return AgentKey(
      id: json['id'] as String,
      keyPrefix: json['key_prefix'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      revokedAt: json['revoked_at'] != null
          ? DateTime.parse(json['revoked_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key_prefix': keyPrefix,
      'created_at': createdAt.toIso8601String(),
      'revoked_at': revokedAt?.toIso8601String(),
    };
  }
}

class MintAgentResponse {
  final String agentId;
  final String keyId;
  final String key;
  final String note;

  MintAgentResponse({
    required this.agentId,
    required this.keyId,
    required this.key,
    required this.note,
  });

  factory MintAgentResponse.fromJson(Map<String, dynamic> json) {
    return MintAgentResponse(
      agentId: json['agent_id'] as String,
      keyId: json['key_id'] as String,
      key: json['key'] as String,
      note: json['note'] as String? ?? '',
    );
  }
}

class MintKeyResponse {
  final String agentId;
  final String keyId;
  final String key;
  final String note;

  MintKeyResponse({
    required this.agentId,
    required this.keyId,
    required this.key,
    required this.note,
  });

  factory MintKeyResponse.fromJson(Map<String, dynamic> json) {
    return MintKeyResponse(
      agentId: json['agent_id'] as String,
      keyId: json['key_id'] as String,
      key: json['key'] as String,
      note: json['note'] as String? ?? '',
    );
  }
}

class MintOAuthResponse {
  final String clientId;
  final String clientSecret;
  final String mcpUrl;
  final String agentId;
  final String agentName;
  final String note;

  MintOAuthResponse({
    required this.clientId,
    required this.clientSecret,
    required this.mcpUrl,
    required this.agentId,
    required this.agentName,
    required this.note,
  });

  factory MintOAuthResponse.fromJson(Map<String, dynamic> json) {
    return MintOAuthResponse(
      clientId: json['client_id'] as String,
      clientSecret: json['client_secret'] as String,
      mcpUrl: json['mcp_url'] as String,
      agentId: json['agent_id'] as String,
      agentName: json['agent_name'] as String,
      note: json['note'] as String? ?? '',
    );
  }
}
