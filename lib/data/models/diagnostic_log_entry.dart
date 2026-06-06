enum DiagnosticLogLevel {
  info,
  warning,
  error,
}

class DiagnosticLogEntry {
  const DiagnosticLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
  });

  factory DiagnosticLogEntry.create({
    required DiagnosticLogLevel level,
    required String category,
    required String message,
    DateTime? timestamp,
  }) {
    final resolvedTimestamp = timestamp ?? DateTime.now();
    final normalizedCategory =
        category.trim().isEmpty ? 'general' : category.trim();
    final normalizedMessage = message.trim();
    return DiagnosticLogEntry(
      id: [
        resolvedTimestamp.microsecondsSinceEpoch,
        normalizedCategory,
        normalizedMessage.hashCode & 0x7fffffff,
      ].join('-'),
      timestamp: resolvedTimestamp,
      level: level,
      category: normalizedCategory,
      message: normalizedMessage,
    );
  }

  factory DiagnosticLogEntry.fromJson(Map<String, dynamic> json) {
    return DiagnosticLogEntry(
      id: json['id'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      level: _levelFromName(json['level'] as String?),
      category: (json['category'] as String? ?? 'general').trim(),
      message: (json['message'] as String? ?? '').trim(),
    );
  }

  final String id;
  final DateTime timestamp;
  final DiagnosticLogLevel level;
  final String category;
  final String message;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'category': category,
      'message': message,
    };
  }

  String get levelLabel {
    switch (level) {
      case DiagnosticLogLevel.info:
        return '信息';
      case DiagnosticLogLevel.warning:
        return '警告';
      case DiagnosticLogLevel.error:
        return '错误';
    }
  }

  static DiagnosticLogLevel _levelFromName(String? name) {
    for (final level in DiagnosticLogLevel.values) {
      if (level.name == name) {
        return level;
      }
    }
    return DiagnosticLogLevel.info;
  }
}
