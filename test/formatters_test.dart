import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/core/utils/formatters.dart';

void main() {
  test('compactDateTime normalizes UTC timestamps to local time before display',
      () {
    final utcValue = DateTime.utc(2026, 4, 14, 6, 30);

    expect(
      Formatters.compactDateTime(utcValue),
      Formatters.compactDateTime(utcValue.toLocal()),
    );
  });
}
