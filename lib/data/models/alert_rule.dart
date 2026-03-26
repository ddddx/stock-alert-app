import 'stock_identity.dart';

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
  factory AlertRule({
    required String id,
    required AlertRuleType type,
    required bool enabled,
    required DateTime createdAt,
    String stockCode = '',
    String stockName = '',
    String market = 'SZ',
    bool applyToAllWatchlist = false,
    List<StockIdentity> targetStocks = const [],
    double? moveThresholdPercent,
    int? lookbackMinutes,
    MoveDirection? moveDirection,
    double? stepValue,
    StepMetric? stepMetric,
    double? anchorPrice,
    Map<String, double> anchorPrices = const {},
    Map<String, double> anchorPricesByCode = const {},
    String? note,
  }) {
    final resolvedTargets = _resolveTargets(
      stockCode: stockCode,
      stockName: stockName,
      market: market,
      targetStocks: targetStocks,
    );
    final normalizedAnchors = _normalizeAnchorPrices({
      ...anchorPrices,
      ...anchorPricesByCode,
    });
    final primaryCode = resolvedTargets.primary?.code ?? stockCode.trim();
    if (anchorPrice != null && anchorPrice > 0 && primaryCode.isNotEmpty) {
      normalizedAnchors.putIfAbsent(primaryCode, () => anchorPrice);
    }

    return AlertRule._(
      id: id,
      stockCode: resolvedTargets.primary?.code ?? stockCode.trim(),
      stockName: resolvedTargets.primary?.name ?? stockName.trim(),
      market: resolvedTargets.primary?.normalizedMarket ?? market,
      applyToAllWatchlist: applyToAllWatchlist,
      targetStocks: resolvedTargets.targets,
      type: type,
      enabled: enabled,
      createdAt: createdAt,
      moveThresholdPercent: moveThresholdPercent,
      lookbackMinutes: lookbackMinutes,
      moveDirection: moveDirection,
      stepValue: stepValue,
      stepMetric: stepMetric,
      anchorPricesByCode: normalizedAnchors,
      note: note,
    );
  }

  factory AlertRule.shortWindowMove({
    required String id,
    required double moveThresholdPercent,
    required int lookbackMinutes,
    required MoveDirection moveDirection,
    required bool enabled,
    required DateTime createdAt,
    String stockCode = '',
    String stockName = '',
    String market = 'SZ',
    bool applyToAllWatchlist = false,
    List<StockIdentity> targetStocks = const [],
    String? note,
  }) {
    return AlertRule(
      id: id,
      stockCode: stockCode,
      stockName: stockName,
      market: market,
      applyToAllWatchlist: applyToAllWatchlist,
      targetStocks: targetStocks,
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
    required double stepValue,
    required StepMetric stepMetric,
    required bool enabled,
    required DateTime createdAt,
    String stockCode = '',
    String stockName = '',
    String market = 'SZ',
    bool applyToAllWatchlist = false,
    List<StockIdentity> targetStocks = const [],
    double? anchorPrice,
    Map<String, double> anchorPrices = const {},
    Map<String, double> anchorPricesByCode = const {},
    String? note,
  }) {
    return AlertRule(
      id: id,
      stockCode: stockCode,
      stockName: stockName,
      market: market,
      applyToAllWatchlist: applyToAllWatchlist,
      targetStocks: targetStocks,
      type: AlertRuleType.stepAlert,
      enabled: enabled,
      createdAt: createdAt,
      stepValue: stepValue,
      stepMetric: stepMetric,
      anchorPrice: anchorPrice,
      anchorPrices: anchorPrices,
      anchorPricesByCode: anchorPricesByCode,
      note: note,
    );
  }

  factory AlertRule.fromJson(Map<String, dynamic> json) {
    final fallbackCode = json['stockCode'] as String? ?? '';
    final legacyAnchor = (json['anchorPrice'] as num?)?.toDouble();
    final anchors = _readAnchorPrices(json);
    if (legacyAnchor != null && fallbackCode.trim().isNotEmpty) {
      anchors.putIfAbsent(fallbackCode.trim(), () => legacyAnchor);
    }

    return AlertRule(
      id: json['id'] as String? ?? '',
      stockCode: fallbackCode,
      stockName: json['stockName'] as String? ?? '',
      market: json['market'] as String? ?? 'SZ',
      applyToAllWatchlist: json['applyToAllWatchlist'] as bool? ?? false,
      targetStocks: _readTargetStocks(json),
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
      anchorPricesByCode: anchors,
      note: json['note'] as String?,
    );
  }

  AlertRule._({
    required this.id,
    required this.stockCode,
    required this.stockName,
    required this.market,
    required this.applyToAllWatchlist,
    required List<StockIdentity> targetStocks,
    required this.type,
    required this.enabled,
    required this.createdAt,
    required Map<String, double> anchorPricesByCode,
    this.moveThresholdPercent,
    this.lookbackMinutes,
    this.moveDirection,
    this.stepValue,
    this.stepMetric,
    this.note,
  })  : targetStocks = List<StockIdentity>.unmodifiable(targetStocks),
        anchorPricesByCode = Map<String, double>.unmodifiable(
          anchorPricesByCode,
        );

  final String id;
  final String stockCode;
  final String stockName;
  final String market;
  final bool applyToAllWatchlist;
  final List<StockIdentity> targetStocks;
  final AlertRuleType type;
  final bool enabled;
  final DateTime createdAt;
  final double? moveThresholdPercent;
  final int? lookbackMinutes;
  final MoveDirection? moveDirection;
  final double? stepValue;
  final StepMetric? stepMetric;
  final Map<String, double> anchorPricesByCode;
  final String? note;

  Map<String, double> get anchorPrices => anchorPricesByCode;

  double? get anchorPrice {
    final primaryCode = stockCode.trim();
    if (primaryCode.isNotEmpty) {
      return anchorPricesByCode[primaryCode];
    }
    if (anchorPricesByCode.length == 1) {
      return anchorPricesByCode.values.first;
    }
    return null;
  }

  AlertRule copyWith({
    String? id,
    String? stockCode,
    String? stockName,
    String? market,
    bool? applyToAllWatchlist,
    List<StockIdentity>? targetStocks,
    AlertRuleType? type,
    bool? enabled,
    DateTime? createdAt,
    double? moveThresholdPercent,
    int? lookbackMinutes,
    MoveDirection? moveDirection,
    double? stepValue,
    StepMetric? stepMetric,
    double? anchorPrice,
    Map<String, double>? anchorPrices,
    Map<String, double>? anchorPricesByCode,
    String? note,
  }) {
    return AlertRule(
      id: id ?? this.id,
      stockCode: stockCode ?? this.stockCode,
      stockName: stockName ?? this.stockName,
      market: market ?? this.market,
      applyToAllWatchlist: applyToAllWatchlist ?? this.applyToAllWatchlist,
      targetStocks: targetStocks ?? this.targetStocks,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      moveThresholdPercent: moveThresholdPercent ?? this.moveThresholdPercent,
      lookbackMinutes: lookbackMinutes ?? this.lookbackMinutes,
      moveDirection: moveDirection ?? this.moveDirection,
      stepValue: stepValue ?? this.stepValue,
      stepMetric: stepMetric ?? this.stepMetric,
      anchorPrice: anchorPrice ?? this.anchorPrice,
      anchorPrices: anchorPrices ?? this.anchorPricesByCode,
      anchorPricesByCode: anchorPricesByCode ?? this.anchorPricesByCode,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stockCode': stockCode,
      'stockName': stockName,
      'market': market,
      'applyToAllWatchlist': applyToAllWatchlist,
      'targetStocks': targetStocks.map((item) => item.toJson()).toList(),
      'type': type.name,
      'enabled': enabled,
      'createdAt': createdAt.toIso8601String(),
      'moveThresholdPercent': moveThresholdPercent,
      'lookbackMinutes': lookbackMinutes,
      'moveDirection': moveDirection?.name,
      'stepValue': stepValue,
      'stepMetric': stepMetric?.name,
      'anchorPrice': anchorPrice,
      'anchorPrices': anchorPricesByCode,
      'anchorPricesByCode': anchorPricesByCode,
      'note': note,
    };
  }

  bool get appliesGlobally => applyToAllWatchlist;

  List<StockIdentity> get resolvedTargetStocks {
    if (targetStocks.isNotEmpty) {
      return targetStocks;
    }
    if (stockCode.trim().isEmpty) {
      return const [];
    }
    return [
      StockIdentity(
        code: stockCode.trim(),
        name: stockName.trim(),
        market: market,
      ),
    ];
  }

  List<StockIdentity> resolveTargetStocks(List<StockIdentity> watchlist) {
    if (applyToAllWatchlist) {
      return List<StockIdentity>.unmodifiable(
        _resolveTargets(
          stockCode: stockCode,
          stockName: stockName,
          market: market,
          targetStocks: watchlist,
        ).targets,
      );
    }
    return resolvedTargetStocks;
  }

  bool appliesToCode(String code) {
    if (applyToAllWatchlist) {
      return true;
    }
    return resolvedTargetStocks.any((item) => item.code == code);
  }

  String stateKeyFor(String code) {
    return [
      id,
      code,
      type.name,
      moveThresholdPercent?.toStringAsFixed(4) ?? '',
      lookbackMinutes?.toString() ?? '',
      moveDirection?.name ?? '',
      stepValue?.toStringAsFixed(4) ?? '',
      stepMetric?.name ?? '',
      anchorPriceFor(code)?.toStringAsFixed(4) ?? '',
    ].join(':');
  }

  double? anchorPriceFor(String code) => anchorPricesByCode[code];

  String targetsLabel() => targetSummaryLabel();

  String targetSummaryLabel() {
    if (applyToAllWatchlist) {
      return '全部自选股';
    }
    final targets = resolvedTargetStocks;
    if (targets.isEmpty) {
      return '未选择股票';
    }
    if (targets.length == 1) {
      final stock = targets.first;
      return '${stock.name} (${stock.code})';
    }
    return '已选择 ${targets.length} 只股票';
  }

  String get typeLabel {
    switch (type) {
      case AlertRuleType.shortWindowMove:
        return '短时波动';
      case AlertRuleType.stepAlert:
        return '阶梯提醒';
    }
  }

  String get summary {
    switch (type) {
      case AlertRuleType.shortWindowMove:
        final directionLabel = switch (moveDirection ?? MoveDirection.either) {
          MoveDirection.up => '上涨',
          MoveDirection.down => '下跌',
          MoveDirection.either => '波动',
        };
        return '${lookbackMinutes ?? 0} 分钟内$directionLabel >= '
            '${(moveThresholdPercent ?? 0).toStringAsFixed(2)}%';
      case AlertRuleType.stepAlert:
        final unit = stepMetric == StepMetric.percent ? '%' : '元';
        return '每跨过 ${(stepValue ?? 0).toStringAsFixed(2)}$unit 提醒一次';
    }
  }

  static _ResolvedTargets _resolveTargets({
    required String stockCode,
    required String stockName,
    required String market,
    required List<StockIdentity> targetStocks,
  }) {
    final resolved = <StockIdentity>[];
    final seen = <String>{};

    void addTarget(StockIdentity stock) {
      final code = stock.code.trim();
      if (code.isEmpty || !seen.add(code)) {
        return;
      }
      resolved.add(
        stock.copyWith(
          code: code,
          name: stock.name.trim(),
          market: stock.normalizedMarket,
        ),
      );
    }

    for (final stock in targetStocks) {
      addTarget(stock);
    }

    if (resolved.isEmpty && stockCode.trim().isNotEmpty) {
      addTarget(
        StockIdentity(
          code: stockCode.trim(),
          name: stockName.trim(),
          market: market,
        ),
      );
    }

    return _ResolvedTargets(
      targets: List<StockIdentity>.unmodifiable(resolved),
      primary: resolved.isEmpty ? null : resolved.first,
    );
  }

  static List<StockIdentity> _readTargetStocks(Map<String, dynamic> json) {
    final rawTargets = json['targetStocks'];
    if (rawTargets is! List) {
      return const [];
    }

    return rawTargets
        .whereType<Map>()
        .map((item) => StockIdentity.fromJson(item.cast<String, dynamic>()))
        .where((item) => item.code.trim().isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, double> _readAnchorPrices(Map<String, dynamic> json) {
    final rawAnchors = json['anchorPricesByCode'] ?? json['anchorPrices'];
    if (rawAnchors is! Map) {
      return <String, double>{};
    }

    final anchors = <String, double>{};
    rawAnchors.forEach((key, value) {
      final code = key.toString().trim();
      final price = switch (value) {
        num() => value.toDouble(),
        String() => double.tryParse(value.trim()),
        _ => null,
      };
      if (code.isNotEmpty && price != null && price > 0) {
        anchors[code] = price;
      }
    });
    return anchors;
  }

  static Map<String, double> _normalizeAnchorPrices(
    Map<String, double> anchorPrices,
  ) {
    final normalized = <String, double>{};
    anchorPrices.forEach((key, value) {
      final code = key.trim();
      if (code.isEmpty || value <= 0) {
        return;
      }
      normalized[code] = value;
    });
    return normalized;
  }
}

class _ResolvedTargets {
  const _ResolvedTargets({
    required this.targets,
    required this.primary,
  });

  final List<StockIdentity> targets;
  final StockIdentity? primary;
}
