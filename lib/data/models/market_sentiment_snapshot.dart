class MarketSentimentSnapshot {
  const MarketSentimentSnapshot({
    required this.advancingCount,
    required this.decliningCount,
    required this.flatCount,
    required this.limitUpCount,
    required this.capturedAt,
  });

  factory MarketSentimentSnapshot.fromJson(Map<String, dynamic> json) {
    return MarketSentimentSnapshot(
      advancingCount: (json['advancingCount'] as num?)?.toInt() ?? 0,
      decliningCount: (json['decliningCount'] as num?)?.toInt() ?? 0,
      flatCount: (json['flatCount'] as num?)?.toInt() ?? 0,
      limitUpCount: (json['limitUpCount'] as num?)?.toInt() ?? 0,
      capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final int advancingCount;
  final int decliningCount;
  final int flatCount;
  final int limitUpCount;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() {
    return {
      'advancingCount': advancingCount,
      'decliningCount': decliningCount,
      'flatCount': flatCount,
      'limitUpCount': limitUpCount,
      'capturedAt': capturedAt.toIso8601String(),
    };
  }
}
