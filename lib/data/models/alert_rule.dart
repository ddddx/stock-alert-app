enum AlertRuleType {
  shortWindowMove,
  stepAlert,
}

enum MoveDirection {
  up,
  down,
  either,
}

enum StepMetric {
  price,
  percent,
}

class AlertRule {
  const AlertRule({
    required this.id,
    required this.stockCode,
    required this.stockName,
    required this.market,
    required this.type,
    required this.enabled,
    required this.createdAt,
    this.moveThresholdPercent,
    this.lookbackMinutes,
    this.moveDirection,
    this.stepValue,
    this.stepMetric,
    this.anchorPrice,
    this.note,
  });

  factory AlertRule.shortWindowMove({
    required String id,
    required String stockCode,
    required String stockName,
    required String market,
    required double moveThresholdPercent,
    required int lookbackMinutes,
    required MoveDirection moveDirection,
    required bool enabled,
    required DateTime createdAt,
    String? note,
  }) {
    return AlertRule(
      id: id,
      stockCode: stockCode,
      stockName: stockName,
      market: market,
      type: AlertRuleType.shortWindowMove,
      enabled: enabled,
      createdAt: createdAt,
      moveThresholdPercent: moveThresholdPercent,
      lookbackMinutes: lookbackMinutes,
      moveDirection: moveDirection,
      note: note,
    );
  }

  factory AlertRule.stepAlert({
    required String id,
    required String stockCode,
    required String stockName,
    required String market,
    required double stepValue,
    required StepMetric stepMetric,
    required bool enabled,
    required DateTime createdAt,
    double? anchorPrice,
    String? note,
  }) {
    return AlertRule(
      id: id,
      stockCode: stockCode,
      stockName: stockName,
      market: market,
      type: AlertRuleType.stepAlert,
      enabled: enabled,
      createdAt: createdAt,
      stepValue: stepValue,
      stepMetric: stepMetric,
      anchorPrice: anchorPrice,
      note: note,
    );
  }

  final String id;
  final String stockCode;
  final String stockName;
  final String market;
  final AlertRuleType type;
  final bool enabled;
  final DateTime createdAt;
  final double? moveThresholdPercent;
  final int? lookbackMinutes;
  final MoveDirection? moveDirection;
  final double? stepValue;
  final StepMetric? stepMetric;
  final double? anchorPrice;
  final String? note;

  AlertRule copyWith({
    String? id,
    String? stockCode,
    String? stockName,
    String? market,
    AlertRuleType? type,
    bool? enabled,
    DateTime? createdAt,
    double? moveThresholdPercent,
    int? lookbackMinutes,
    MoveDirection? moveDirection,
    double? stepValue,
    StepMetric? stepMetric,
    double? anchorPrice,
    String? note,
  }) {
    return AlertRule(
      id: id ?? this.id,
      stockCode: stockCode ?? this.stockCode,
      stockName: stockName ?? this.stockName,
      market: market ?? this.market,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      moveThresholdPercent: moveThresholdPercent ?? this.moveThresholdPercent,
      lookbackMinutes: lookbackMinutes ?? this.lookbackMinutes,
      moveDirection: moveDirection ?? this.moveDirection,
      stepValue: stepValue ?? this.stepValue,
      stepMetric: stepMetric ?? this.stepMetric,
      anchorPrice: anchorPrice ?? this.anchorPrice,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stockCode': stockCode,
      'stockName': stockName,
      'market': market,
      'type': type.name,
      'enabled': enabled,
      'createdAt': createdAt.toIso8601String(),
      'moveThresholdPercent': moveThresholdPercent,
      'lookbackMinutes': lookbackMinutes,
      'moveDirection': moveDirection?.name,
      'stepValue': stepValue,
      'stepMetric': stepMetric?.name,
      'anchorPrice': anchorPrice,
      'note': note,
    };
  }

  factory AlertRule.fromJson(Map<String, dynamic> json) {
    return AlertRule(
      id: json['id'] as String? ?? '',
      stockCode: json['stockCode'] as String? ?? '',
      stockName: json['stockName'] as String? ?? '',
      market: json['market'] as String? ?? 'SZ',
      type: AlertRuleType.values.byName(
        json['type'] as String? ?? AlertRuleType.shortWindowMove.name,
      ),
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      moveThresholdPercent: (json['moveThresholdPercent'] as num?)?.toDouble(),
      lookbackMinutes: json['lookbackMinutes'] as int?,
      moveDirection: json['moveDirection'] == null
          ? null
          : MoveDirection.values.byName(json['moveDirection'] as String),
      stepValue: (json['stepValue'] as num?)?.toDouble(),
      stepMetric: json['stepMetric'] == null
          ? null
          : StepMetric.values.byName(json['stepMetric'] as String),
      anchorPrice: (json['anchorPrice'] as num?)?.toDouble(),
      note: json['note'] as String?,
    );
  }

  String get typeLabel {
    switch (type) {
      case AlertRuleType.shortWindowMove:
        return '短时大幅波动';
      case AlertRuleType.stepAlert:
        return '台阶提醒';
    }
  }

  String get summary {
    switch (type) {
      case AlertRuleType.shortWindowMove:
        final directionLabel = switch (moveDirection ?? MoveDirection.either) {
          MoveDirection.up => '上涨',
          MoveDirection.down => '下跌',
          MoveDirection.either => '涨跌',
        };
        return '${lookbackMinutes ?? 0} 分钟内$directionLabel超过 ${(moveThresholdPercent ?? 0).toStringAsFixed(2)}%';
      case AlertRuleType.stepAlert:
        final metricLabel = switch (stepMetric ?? StepMetric.price) {
          StepMetric.price => '价格',
          StepMetric.percent => '涨跌幅',
        };
        final unit = stepMetric == StepMetric.percent ? '%' : '元';
        return '每 $metricLabel 变化 ${(stepValue ?? 0).toStringAsFixed(2)}$unit 提醒';
    }
  }
}
