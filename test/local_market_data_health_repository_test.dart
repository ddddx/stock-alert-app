import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/market_data_health_snapshot.dart';
import 'package:stock_alert_app/data/repositories/local_market_data_health_repository.dart';
import 'package:stock_alert_app/services/storage/json_file_store.dart';

void main() {
  test('market data health repository persists, reloads, and clears snapshot',
      () async {
    final root =
        await Directory.systemTemp.createTemp('market_data_health_repo_test_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'market_data_health.json');
    await store.initialize(root.path);

    final repository = LocalMarketDataHealthRepository(store: store);
    await repository.initialize();
    expect(repository.getSnapshot(), isNull);

    final snapshot = MarketDataHealthSnapshot(
      providerId: 'ashare',
      providerName: '聚合 A 股',
      checkedAt: DateTime(2026, 3, 23, 10, 0),
      requestedCount: 2,
      successCount: 1,
      failedCount: 1,
      fallbackUsed: true,
      latestQuoteAt: DateTime(2026, 3, 23, 9, 59),
      lastError: 'SocketException: network down',
      updatedBy: 'flutter',
    );
    await repository.replace(snapshot);

    final reloaded = LocalMarketDataHealthRepository(store: store);
    await reloaded.initialize();
    expect(reloaded.getSnapshot()?.providerId, 'ashare');
    expect(reloaded.getSnapshot()?.providerName, '聚合 A 股');
    expect(reloaded.getSnapshot()?.checkedAt, DateTime(2026, 3, 23, 10, 0));
    expect(reloaded.getSnapshot()?.requestedCount, 2);
    expect(reloaded.getSnapshot()?.successCount, 1);
    expect(reloaded.getSnapshot()?.failedCount, 1);
    expect(reloaded.getSnapshot()?.fallbackUsed, isTrue);
    expect(
      reloaded.getSnapshot()?.latestQuoteAt,
      DateTime(2026, 3, 23, 9, 59),
    );
    expect(reloaded.getSnapshot()?.lastError, contains('network down'));

    await reloaded.clear();
    expect(reloaded.getSnapshot(), isNull);

    final cleared = LocalMarketDataHealthRepository(store: store);
    await cleared.initialize();
    expect(cleared.getSnapshot(), isNull);
  });
}
