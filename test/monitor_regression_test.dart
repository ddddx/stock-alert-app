import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/alert_rule.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';
import 'package:stock_alert_app/services/alerts/alert_rule_engine.dart';

void main() {
  test('short-window alert message stays on percent-only speech', () {
    final engine = AlertRuleEngine(messageBuilder: AlertMessageBuilder());
    final rule = AlertRule.shortWindowMove(
      id: 'rule-short',
      stockCode: '600519',
      stockName: '贵州茅台',
      market: 'SH',
      moveThresholdPercent: 1.0,
      lookbackMinutes: 5,
      moveDirection: MoveDirection.either,
      enabled: true,
      createdAt: DateTime(2026, 1, 1),
    );

    final firstPass = engine.processQuotes(
      rules: [rule],
      quotes: [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1500,
          previousClose: 1490,
          changeAmount: 10,
          changePercent: 0.67,
          openPrice: 1492,
          highPrice: 1500,
          lowPrice: 1490,
          volume: 1000,
          timestamp: DateTime(2026, 1, 1, 9, 30),
        ),
      ],
    );

    final secondPass = engine.processQuotes(
      rules: [rule],
      quotes: [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1520,
          previousClose: 1490,
          changeAmount: 30,
          changePercent: 2.01,
          openPrice: 1492,
          highPrice: 1520,
          lowPrice: 1490,
          volume: 1200,
          timestamp: DateTime(2026, 1, 1, 9, 35),
        ),
      ],
    );

    expect(firstPass, isEmpty);
    expect(secondPass, hasLength(1));
    expect(secondPass.first.message, contains('贵州茅台'));
    expect(secondPass.first.message, contains('上涨1.33%'));
    expect(secondPass.first.message, contains('当前涨跌幅+2.01%'));
    expect(secondPass.first.message, isNot(contains('600519')));
    expect(secondPass.first.message, isNot(contains('最新价')));
  });

  test('price step alert message stays on price-only speech', () {
    final engine = AlertRuleEngine(messageBuilder: AlertMessageBuilder());
    final rule = AlertRule.stepAlert(
      id: 'rule-step-price',
      stockCode: '000001',
      stockName: '平安银行',
      market: 'SZ',
      stepValue: 0.5,
      stepMetric: StepMetric.price,
      enabled: true,
      createdAt: DateTime(2026, 1, 1),
      anchorPrice: 10.0,
    );

    final firstPass = engine.processQuotes(
      rules: [rule],
      quotes: [
        StockQuoteSnapshot(
          code: '000001',
          name: '平安银行',
          market: 'SZ',
          lastPrice: 10.1,
          previousClose: 10.0,
          changeAmount: 0.1,
          changePercent: 1.0,
          openPrice: 10.0,
          highPrice: 10.1,
          lowPrice: 9.9,
          volume: 800,
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
          lastPrice: 10.6,
          previousClose: 10.0,
          changeAmount: 0.6,
          changePercent: 6.0,
          openPrice: 10.0,
          highPrice: 10.6,
          lowPrice: 9.9,
          volume: 900,
          timestamp: DateTime(2026, 1, 1, 9, 31),
        ),
      ],
    );

    expect(firstPass, isEmpty);
    expect(secondPass, hasLength(1));
    expect(secondPass.first.message, contains('平安银行'));
    expect(secondPass.first.message, contains('上涨跨越价格台阶'));
    expect(secondPass.first.message, contains('价格从'));
    expect(secondPass.first.message, contains('最新价¥10.60'));
    expect(secondPass.first.message, isNot(contains('%')));
    expect(secondPass.first.message, isNot(contains('000001')));
  });
}
