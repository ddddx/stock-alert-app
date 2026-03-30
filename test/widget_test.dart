import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/alert_rule.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';
import 'package:stock_alert_app/services/alerts/alert_rule_engine.dart';

void main() {
  test('step alert triggers when crossing a percent band', () {
    final engine = AlertRuleEngine(messageBuilder: AlertMessageBuilder());
    final rule = AlertRule.stepAlert(
      id: 'rule-1',
      stockCode: '000001',
      stockName: '平安银行',
      market: 'SZ',
      stepValue: 0.5,
      stepMetric: StepMetric.percent,
      enabled: true,
      createdAt: DateTime(2026, 1, 1),
    );

    final firstPass = engine.processQuotes(
      rules: [rule],
      quotes: [
        StockQuoteSnapshot(
          code: '000001',
          name: '平安银行',
          market: 'SZ',
          lastPrice: 10,
          previousClose: 10,
          changeAmount: 0.2,
          changePercent: 0.2,
          openPrice: 10,
          highPrice: 10.1,
          lowPrice: 9.9,
          volume: 1000,
          timestamp: DateTime(2026, 1, 1, 9, 30),
        ),
      ],
    );

    final secondPass = engine.processQuotes(
      rules: [rule],
      quotes: [
        StockQuoteSnapshot(
          code: '000001',
          name: '平安银行',
          market: 'SZ',
          lastPrice: 10.08,
          previousClose: 10,
          changeAmount: 0.08,
          changePercent: 0.8,
          openPrice: 10,
          highPrice: 10.08,
          lowPrice: 9.9,
          volume: 1200,
          timestamp: DateTime(2026, 1, 1, 9, 31),
        ),
      ],
    );

    expect(firstPass, isEmpty);
    expect(secondPass, hasLength(1));
    expect(secondPass.first.message, contains('平安银行'));
    expect(secondPass.first.message, contains('越过0.50%台阶'));
    expect(secondPass.first.message, contains('当前涨跌幅+0.80%'));
    expect(secondPass.first.message, isNot(contains('000001')));
    expect(secondPass.first.message, isNot(contains('¥0.08')));
  });
}
