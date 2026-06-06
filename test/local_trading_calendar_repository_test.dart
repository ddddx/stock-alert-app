import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/trading_calendar.dart';
import 'package:stock_alert_app/data/repositories/local_trading_calendar_repository.dart';
import 'package:stock_alert_app/services/storage/json_file_store.dart';

void main() {
  test('initialize writes bundled calendar when storage is empty', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-calendar-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'trading_calendar.json');
    await store.initialize(directory.path);
    final repository = LocalTradingCalendarRepository(store: store);

    await repository.initialize();

    final calendar = repository.getCalendar();
    expect(calendar.closedDates, AshareTradingCalendar.defaultClosedDates);
    expect(calendar.openDates, isEmpty);

    final persisted = await store.readObject();
    expect(persisted, isNotNull);
    expect(persisted!['schemaVersion'], AshareTradingCalendar.schemaVersion);
    expect(persisted['closedDates'], contains('2026-05-04'));
    expect(persisted['openDates'], isEmpty);
  });

  test('initialize loads custom closed and open dates', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-calendar-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'trading_calendar.json');
    await store.initialize(directory.path);
    await store.writeJson({
      'schemaVersion': AshareTradingCalendar.schemaVersion,
      'closedDates': ['2026-03-24'],
      'openDates': ['2026-03-28'],
      'updatedAt': '2026-03-01T00:00:00.000Z',
    });

    final repository = LocalTradingCalendarRepository(store: store);
    await repository.initialize();

    final calendar = repository.getCalendar();
    expect(calendar.closedDates, {'2026-03-24'});
    expect(calendar.openDates, {'2026-03-28'});
    expect(calendar.isTradingDay(DateTime(2026, 3, 24, 10)), isFalse);
    expect(calendar.isTradingDay(DateTime(2026, 3, 28, 10)), isTrue);
  });

  test('replace and resetToBundled persist the active calendar', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-calendar-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'trading_calendar.json');
    await store.initialize(directory.path);
    final repository = LocalTradingCalendarRepository(store: store);
    await repository.initialize();

    await repository.replace(
      const AshareTradingCalendar(
        closedDates: {'2026-03-24'},
        openDates: {'2026-03-28'},
      ),
    );

    var persisted = await store.readObject();
    expect(persisted!['closedDates'], ['2026-03-24']);
    expect(persisted['openDates'], ['2026-03-28']);

    await repository.resetToBundled();

    persisted = await store.readObject();
    expect(persisted!['closedDates'], contains('2026-05-04'));
    expect(persisted['openDates'], isEmpty);
    expect(repository.getCalendar().closedDates,
        AshareTradingCalendar.defaultClosedDates);
  });
}
