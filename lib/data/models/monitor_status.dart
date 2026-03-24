class MonitorStatus {
  const MonitorStatus({
    required this.serviceEnabled,
    required this.soundEnabled,
    required this.lastCheckAt,
    required this.lastMessage,
  });

  final bool serviceEnabled;
  final bool soundEnabled;
  final DateTime? lastCheckAt;
  final String lastMessage;

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
}
