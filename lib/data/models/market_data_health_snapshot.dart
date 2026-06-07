class MarketDataHealthSnapshot {
  const MarketDataHealthSnapshot({
    required this.providerId,
    required this.providerName,
    required this.checkedAt,
    required this.requestedCount,
    required this.successCount,
    required this.failedCount,
    required this.fallbackUsed,
    this.latestQuoteAt,
    this.lastError = '',
    this.updatedBy = 'flutter',
  });

  factory MarketDataHealthSnapshot.fromJson(Map<String, dynamic> json) {
    return MarketDataHealthSnapshot(
      providerId: (json['providerId'] as String? ?? 'ashare').trim(),
      providerName: (json['providerName'] as String? ?? '聚合 A 股').trim(),
      checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      requestedCount: _nonNegativeInt(json['requestedCount']),
      successCount: _nonNegativeInt(json['successCount']),
      failedCount: _nonNegativeInt(json['failedCount']),
      fallbackUsed: json['fallbackUsed'] as bool? ?? false,
      latestQuoteAt: DateTime.tryParse(json['latestQuoteAt'] as String? ?? ''),
      lastError: (json['lastError'] as String? ?? '').trim(),
      updatedBy: (json['updatedBy'] as String? ?? 'flutter').trim(),
    );
  }

  static const int schemaVersion = 1;

  final String providerId;
  final String providerName;
  final DateTime checkedAt;
  final int requestedCount;
  final int successCount;
  final int failedCount;
  final bool fallbackUsed;
  final DateTime? latestQuoteAt;
  final String lastError;
  final String updatedBy;

  bool get hasFailures => failedCount > 0 || lastError.isNotEmpty;
  bool get hasPartialSuccess => successCount > 0 && failedCount > 0;
  bool get allRequestedQuotesSucceeded =>
      requestedCount > 0 && successCount == requestedCount && failedCount == 0;

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'providerId': providerId,
      'providerName': providerName,
      'checkedAt': checkedAt.toIso8601String(),
      'requestedCount': requestedCount,
      'successCount': successCount,
      'failedCount': failedCount,
      'fallbackUsed': fallbackUsed,
      'latestQuoteAt': latestQuoteAt?.toIso8601String(),
      'lastError': lastError,
      'updatedBy': updatedBy,
    };
  }

  static int _nonNegativeInt(Object? value) {
    final parsed = switch (value) {
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value.trim()),
      _ => null,
    };
    return (parsed ?? 0).clamp(0, 1 << 31).toInt();
  }
}
