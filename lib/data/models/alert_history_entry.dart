import 'alert_rule.dart';

class AlertHistoryEntry {
  const AlertHistoryEntry({
    required this.id,
    required this.ruleId,
    required this.ruleType,
    required this.stockCode,
    required this.stockName,
    required this.market,
    required this.triggeredAt,
    required this.currentPrice,
    required this.referencePrice,
    required this.changeAmount,
    required this.changePercent,
    required this.message,
    required this.spokenText,
    required this.playedSound,
  });

  final String id;
  final String ruleId;
  final AlertRuleType ruleType;
  final String stockCode;
  final String stockName;
  final String market;
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
      'stockName': stockName,
      'market': market,
      'triggeredAt': triggeredAt.toIso8601String(),
      'currentPrice': currentPrice,
      'referencePrice': referencePrice,
      'changeAmount': changeAmount,
      'changePercent': changePercent,
      'message': message,
      'spokenText': spokenText,
      'playedSound': playedSound,
    };
  }
}
