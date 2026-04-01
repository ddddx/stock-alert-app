import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';

void main() {
  test('message builder falls back to stock code when name is unreadable', () {
    final quote = StockQuoteSnapshot(
      code: '000001',
      name: '�bad',
      market: 'SZ',
      lastPrice: 10.2,
      previousClose: 10.0,
      changeAmount: 0.2,
      changePercent: 2.0,
      openPrice: 10.0,
      highPrice: 10.3,
      lowPrice: 9.9,
      volume: 1000,
      timestamp: DateTime(2026, 4, 1, 10, 0),
    );

    final text = AlertMessageBuilder().buildPreviewText(quote);

    expect(text, contains('000001'));
    expect(text, isNot(contains('�bad')));
  });
}
