// ignore_for_file: avoid_print

import 'package:stock_alert_app/services/background/monitoring_policy.dart';

void main() {
  const marketHours = AshareMarketHours();

  assert(normalizeMonitorPollIntervalSeconds(0) == 1);
  assert(normalizeMonitorPollIntervalSeconds(5) == 5);
  assert(normalizeMonitorPollIntervalSeconds(999) == 300);

  assert(marketHours.isTradingTime(DateTime(2026, 3, 23, 11, 29)));
  assert(!marketHours.isTradingTime(DateTime(2026, 3, 23, 11, 30)));
  assert(!marketHours.isTradingTime(DateTime(2026, 3, 23, 12, 0)));
  assert(marketHours.isTradingTime(DateTime(2026, 3, 23, 13, 0)));

  final nextSession =
      marketHours.nextSessionStart(DateTime(2026, 3, 28, 10, 0));
  assert(nextSession.year == 2026);
  assert(nextSession.month == 3);
  assert(nextSession.day == 30);
  assert(nextSession.hour == 9);
  assert(nextSession.minute == 30);

  final message = marketHours.buildClosedMessage(DateTime(2026, 3, 28, 10, 0));
  assert(message.contains('当前不在A股交易时段'));
  assert(message.contains('09:30'));

  print('monitoring_policy_check: ok');
}
