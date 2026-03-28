class WebDavConfig {
  const WebDavConfig({
    required this.endpoint,
    required this.username,
  });

  factory WebDavConfig.empty() {
    return const WebDavConfig(endpoint: '', username: '');
  }

  factory WebDavConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return WebDavConfig.empty();
    }
    return WebDavConfig(
      endpoint: json['endpoint'] as String? ?? '',
      username: json['username'] as String? ?? '',
    );
  }

  final String endpoint;
  final String username;

  bool get isConfigured =>
      endpoint.trim().isNotEmpty && username.trim().isNotEmpty;

  WebDavConfig copyWith({
    String? endpoint,
    String? username,
  }) {
    return WebDavConfig(
      endpoint: endpoint ?? this.endpoint,
      username: username ?? this.username,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'endpoint': endpoint,
      'username': username,
    };
  }
}
