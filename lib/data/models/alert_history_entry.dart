import 'alert_rule.dart';
import '../../core/utils/stock_text_sanitizer.dart';

class AlertHistoryEntry {
  const AlertHistoryEntry({
    required this.id,
    required this.ruleId,
    required this.ruleType,
    required this.stockCode,
    required this.stockName,
    required this.market,
    this.securityTypeName = '',
    this.priceDecimalDigits,
    required this.triggeredAt,
    required this.currentPrice,
    required this.referencePrice,
    required this.changeAmount,
    required this.changePercent,
    required this.message,
    required this.spokenText,
    required this.playedSound,
  });

  factory AlertHistoryEntry.fromJson(Map<String, dynamic> json) {
    final stockCode = json['stockCode'] as String? ?? '';
    final stockName = StockTextSanitizer.sanitizeStockName(
      json['stockName'] as String?,
      stockCode: stockCode,
    );
    return AlertHistoryEntry(
      id: json['id'] as String? ?? '',
      ruleId: json['ruleId'] as String? ?? '',
      ruleType: AlertRuleType.values.byName(
        json['ruleType'] as String? ?? AlertRuleType.shortWindowMove.name,
      ),
      stockCode: stockCode,
      stockName: stockName,
      market: json['market'] as String? ?? 'SZ',
      securityTypeName: json['securityTypeName'] as String? ?? '',
      priceDecimalDigits: (json['priceDecimalDigits'] as num?)?.toInt(),
      triggeredAt: DateTime.tryParse(json['triggeredAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      currentPrice: (json['currentPrice'] as num?)?.toDouble() ?? 0,
      referencePrice: (json['referencePrice'] as num?)?.toDouble() ?? 0,
      changeAmount: (json['changeAmount'] as num?)?.toDouble() ?? 0,
      changePercent: (json['changePercent'] as num?)?.toDouble() ?? 0,
      message: StockTextSanitizer.sanitizeReadableText(
        json['message'] as String? ?? '',
        stockCode: stockCode,
        rawStockName: json['stockName'] as String? ?? '',
        fallbackStockName: stockName,
      ),
      spokenText: StockTextSanitizer.sanitizeReadableText(
        json['spokenText'] as String? ?? '',
        stockCode: stockCode,
        rawStockName: json['stockName'] as String? ?? '',
        fallbackStockName: stockName,
      ),
      playedSound: json['playedSound'] as bool? ?? false,
    );
  }

  final String id;
  final String ruleId;
  final AlertRuleType ruleType;
  final String stockCode;
  final String stockName;
  final String market;
  final String securityTypeName;
  final int? priceDecimalDigits;
  final DateTime triggeredAt;
  final double currentPrice;
  final double referencePrice;
  final double changeAmount;
  final double changePercent;
  final String message;
  final String spokenText;
  final bool playedSound;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ruleId': ruleId,
      'ruleType': ruleType.name,
      'stockCode': stockCode,
      'stockName': StockTextSanitizer.sanitizeStockName(
        stockName,
        stockCode: stockCode,
      ),
      'market': market,
      'securityTypeName': securityTypeName,
      'priceDecimalDigits': priceDecimalDigits,
      'triggeredAt': triggeredAt.toIso8601String(),
      'currentPrice': currentPrice,
      'referencePrice': referencePrice,
      'changeAmount': changeAmount,
      'changePercent': changePercent,
      'message': StockTextSanitizer.sanitizeReadableText(
        message,
        stockCode: stockCode,
        rawStockName: stockName,
      ),
      'spokenText': StockTextSanitizer.sanitizeReadableText(
        spokenText,
        stockCode: stockCode,
        rawStockName: stockName,
      ),
      'playedSound': playedSound,
    };
  }
}
