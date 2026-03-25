class MonitorStatus {
  const MonitorStatus({
    required this.serviceEnabled,
    required this.soundEnabled,
    required this.lastCheckAt,
    required this.lastMessage,
  });

  factory MonitorStatus.fromJson(Map<String, dynamic> json) {
    return MonitorStatus(
      serviceEnabled: json['serviceEnabled'] as bool? ?? false,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      lastCheckAt: json['lastCheckAt'] == null
          ? null
          : DateTime.tryParse(json['lastCheckAt'] as String),
      lastMessage: json['lastMessage'] as String? ?? '等待首次刷新 A 股行情。',
    );
  }

  MonitorStatus copyWith({
    bool? serviceEnabled,
    bool? soundEnabled,
    DateTime? lastCheckAt,
    String? lastMessage,
  }) {
    return MonitorStatus(
      serviceEnabled: serviceEnabled ?? this.serviceEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }

  final bool serviceEnabled;
  final bool soundEnabled;
  final DateTime? lastCheckAt;
  final String lastMessage;

  Map<String, dynamic> toJson() {
    return {
      'serviceEnabled': serviceEnabled,
      'soundEnabled': soundEnabled,
      'lastCheckAt': lastCheckAt?.toIso8601String(),
      'lastMessage': lastMessage,
    };
  }
}
