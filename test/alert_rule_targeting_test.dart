import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/alert_rule.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';
import 'package:stock_alert_app/services/alerts/alert_rule_engine.dart';

void main() {
  test('global short-window rule can trigger for multiple selected quotes', () {
    final engine = AlertRuleEngine(messageBuilder: AlertMessageBuilder());
    final rule = AlertRule.shortWindowMove(
      id: 'global-short',
      moveThresholdPercent: 1,
      lookbackMinutes: 5,
      moveDirection: MoveDirection.either,
      enabled: true,
      createdAt: DateTime(2026, 1, 1),
      applyToAllWatchlist: true,
      targetStocks: const [
        StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
        StockIdentity(code: '000001', name: '平安银行', market: 'SZ'),
      ],
    );

    engine.processQuotes(
      rules: [rule],
      quotes: [
        _quote(code: '600519', name: '贵州茅台', market: 'SH', lastPrice: 1500, previousClose: 1490, timestamp: DateTime(2026, 1, 1, 9, 30)),
        _quote(code: '000001', name: '平安银行', market: 'SZ', lastPrice: 10, previousClose: 10, timestamp: DateTime(2026, 1, 1, 9, 30)),
      ],
    );

    final triggers = engine.processQuotes(
      rules: [rule],
      quotes: [
        _quote(code: '600519', name: '贵州茅台', market: 'SH', lastPrice: 1520, previousClose: 1490, timestamp: DateTime(2026, 1, 1, 9, 35)),
        _quote(code: '000001', name: '平安银行', market: 'SZ', lastPrice: 10.2, previousClose: 10, timestamp: DateTime(2026, 1, 1, 9, 35)),
      ],
    );

    expect(triggers, hasLength(2));
    expect(triggers.map((item) => item.quote.code), containsAll(['600519', '000001']));
  });

  test('price step rule keeps independent anchors per selected stock', () {
    final engine = AlertRuleEngine(messageBuilder: AlertMessageBuilder());
    final rule = AlertRule.stepAlert(
      id: 'multi-step',
      stepValue: 0.5,
      stepMetric: StepMetric.price,
      enabled: true,
      createdAt: DateTime(2026, 1, 1),
      targetStocks: const [
        StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
        StockIdentity(code: '000001', name: '平安银行', market: 'SZ'),
      ],
      anchorPrices: const {
        '600519': 1500,
        '000001': 10,
      },
    );

    engine.processQuotes(
      rules: [rule],
      quotes: [
        _quote(code: '600519', name: '贵州茅台', market: 'SH', lastPrice: 1500.1, previousClose: 1490, timestamp: DateTime(2026, 1, 1, 9, 30)),
        _quote(code: '000001', name: '平安银行', market: 'SZ', lastPrice: 10.1, previousClose: 10, timestamp: DateTime(2026, 1, 1, 9, 30)),
      ],
    );

    final triggers = engine.processQuotes(
      rules: [rule],
      quotes: [
        _quote(code: '600519', name: '贵州茅台', market: 'SH', lastPrice: 1500.7, previousClose: 1490, timestamp: DateTime(2026, 1, 1, 9, 31)),
        _quote(code: '000001', name: '平安银行', market: 'SZ', lastPrice: 10.7, previousClose: 10, timestamp: DateTime(2026, 1, 1, 9, 31)),
      ],
    );

    expect(triggers, hasLength(2));
    expect(triggers.first.referencePrice, anyOf(1500, 10));
    expect(triggers.last.referencePrice, anyOf(1500, 10));
  });
}

StockQuoteSnapshot _quote({
  required String code,
  required String name,
  required String market,
  required double lastPrice,
  required double previousClose,
  required DateTime timestamp,
}) {
  return StockQuoteSnapshot(
    code: code,
    name: name,
    market: market,
    lastPrice: lastPrice,
    previousClose: previousClose,
    changeAmount: lastPrice - previousClose,
    changePercent: previousClose == 0 ? 0 : (lastPrice - previousClose) / previousClose * 100,
    openPrice: previousClose,
    highPrice: lastPrice,
    lowPrice: previousClose,
    volume: 1000,
    timestamp: timestamp,
  );
}
