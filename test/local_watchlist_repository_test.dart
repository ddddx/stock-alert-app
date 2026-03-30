import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/repositories/local_watchlist_repository.dart';
import 'package:stock_alert_app/services/storage/json_file_store.dart';

void main() {
  test('initialize restores per-stock monitoring state from local storage', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-watchlist-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'watchlist.json');
    await store.initialize(directory.path);
    await store.writeJson([
      {
        'code': '600519',
        'name': '贵州茅台',
        'market': 'SH',
        'monitoringEnabled': false,
      },
    ]);

    final repository = LocalWatchlistRepository(store: store);
    await repository.initialize();

    expect(repository.getAll().single.monitoringEnabled, isFalse);
  });

  test('updateMonitoringEnabled persists the new value', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-watchlist-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'watchlist.json');
    await store.initialize(directory.path);
    final repository = LocalWatchlistRepository(store: store);
    await repository.initialize();

    await repository.updateMonitoringEnabled('600519', false);

    expect(repository.getAll().first.monitoringEnabled, isFalse);

    final reloaded = LocalWatchlistRepository(store: store);
    await reloaded.initialize();
    expect(reloaded.getAll().first.monitoringEnabled, isFalse);
  });
}
