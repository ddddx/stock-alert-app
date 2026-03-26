import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/services/background/monitoring_policy.dart';

void main() {
  const marketHours = AshareMarketHours();

  test('poll interval normalization allows one-second monitoring', () {
    expect(normalizeMonitorPollIntervalSeconds(0), 1);
    expect(normalizeMonitorPollIntervalSeconds(5), 5);
    expect(normalizeMonitorPollIntervalSeconds(999), 300);
  });

  test('market hours treat midday break as closed and afternoon as open', () {
    expect(marketHours.isTradingTime(DateTime(2026, 3, 23, 11, 29)), isTrue);
    expect(marketHours.isTradingTime(DateTime(2026, 3, 23, 11, 30)), isFalse);
    expect(marketHours.isTradingTime(DateTime(2026, 3, 23, 12, 59)), isFalse);
    expect(marketHours.isTradingTime(DateTime(2026, 3, 23, 13, 0)), isTrue);
  });

  test('market hours skip weekends and resume on next weekday morning', () {
    final saturday = DateTime(2026, 3, 28, 10, 0);

    expect(marketHours.isTradingTime(saturday), isFalse);

    final nextSession = marketHours.nextSessionStart(saturday);
    expect(nextSession.year, 2026);
    expect(nextSession.month, 3);
    expect(nextSession.day, 30);
    expect(nextSession.hour, 9);
    expect(nextSession.minute, 30);

    final message = marketHours.buildClosedMessage(saturday);
    expect(message, contains('Outside A-share trading hours'));
    expect(message, contains('09:30'));
  });
}
