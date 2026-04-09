import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/alert_rule.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';

void main() {
  final builder = AlertMessageBuilder();
  final quote = StockQuoteSnapshot(
    code: '600519',
    name: '贵州茅台',
    market: 'SH',
    lastPrice: 1688.00,
    previousClose: 1650.00,
    changeAmount: 38.00,
    changePercent: 2.30,
    openPrice: 1660.00,
    highPrice: 1690.00,
    lowPrice: 1658.00,
    volume: 1000,
    timestamp: DateTime(2026, 3, 29, 9, 45),
  );

  test('short window message only announces name and percent movement', () {
    final text = builder.buildShortWindowMessage(
      rule: AlertRule.shortWindowMove(
        id: 'rule-1',
        moveThresholdPercent: 1.2,
        lookbackMinutes: 5,
        moveDirection: MoveDirection.either,
        enabled: true,
        createdAt: DateTime(2026, 3, 29),
      ),
      current: quote,
      changeAmount: 25.5,
      changePercent: 1.55,
    );

    expect(text, contains('贵州茅台'));
    expect(text, isNot(contains('600519')));
    expect(text, contains('短时波动提醒'));
    expect(text, contains('上涨1.55%'));
    expect(text, contains('当前涨跌幅+2.30%'));
    expect(text, isNot(contains('最新价')));
  });

  test('percent step message only announces percent movement', () {
    final text = builder.buildStepAlertMessage(
      rule: AlertRule.stepAlert(
        id: 'rule-2',
        stepValue: 0.5,
        stepMetric: StepMetric.percent,
        enabled: true,
        createdAt: DateTime(2026, 3, 29),
      ),
      current: quote,
      previousIndex: 3,
      currentIndex: 4,
      referenceValue: 1650,
      crossedAmount: 38,
      crossedPercent: 2.30,
    );

    expect(text, contains('贵州茅台'));
    expect(text, isNot(contains('600519')));
    expect(text, contains('阶梯提醒'));
    expect(text, contains('从+1.50%台阶跨到+2.00%台阶'));
    expect(text, contains('当前涨跌幅+2.30%'));
    expect(text, isNot(contains('最新价')));
  });

  test('percent step message avoids zero threshold phrasing', () {
    final text = builder.buildStepAlertMessage(
      rule: AlertRule.stepAlert(
        id: 'rule-4',
        stepValue: 0.5,
        stepMetric: StepMetric.percent,
        enabled: true,
        createdAt: DateTime(2026, 3, 29),
      ),
      current: quote,
      previousIndex: 0,
      currentIndex: 1,
      referenceValue: 1650,
      crossedAmount: 8.25,
      crossedPercent: 0.50,
    );

    expect(text, isNot(contains('0.00%')));
    expect(text, contains('达到+0.50%台阶'));
  });

  test('price step message only announces price movement', () {
    final text = builder.buildStepAlertMessage(
      rule: AlertRule.stepAlert(
        id: 'rule-3',
        stepValue: 0.5,
        stepMetric: StepMetric.price,
        enabled: true,
        createdAt: DateTime(2026, 3, 29),
      ),
      current: quote,
      previousIndex: 3,
      currentIndex: 4,
      referenceValue: 1650,
      crossedAmount: 38,
      crossedPercent: 2.30,
    );

    expect(text, contains('贵州茅台'));
    expect(text, isNot(contains('600519')));
    expect(text, contains('价格从'));
    expect(text, contains('上涨跨越价格台阶'));
    expect(text, contains('跨到'));
    expect(text, contains('最新价'));
    expect(text, isNot(contains('涨跌幅')));
  });
}
