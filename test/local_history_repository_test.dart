import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/repositories/local_history_repository.dart';
import 'package:stock_alert_app/services/storage/json_file_store.dart';

void main() {
  test('history initialization sanitizes unreadable stock names and texts',
      () async {
    final root = await Directory.systemTemp.createTemp('history_repo_test_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    const unreadableName = '�bad';
    final store = JsonFileStore(fileName: 'history.json');
    await store.initialize(root.path);
    await store.writeJson([
      {
        'id': '1',
        'ruleId': 'rule-1',
        'ruleType': 'shortWindowMove',
        'stockCode': '600519',
        'stockName': unreadableName,
        'market': 'SH',
        'triggeredAt': DateTime(2026, 4, 1, 9, 35).toIso8601String(),
        'currentPrice': 1500.0,
        'referencePrice': 1490.0,
        'changeAmount': 10.0,
        'changePercent': 0.67,
        'message': 'trigger $unreadableName now',
        'spokenText': 'speak $unreadableName now',
        'playedSound': true,
      },
    ]);

    final repository = LocalHistoryRepository(store: store);
    await repository.initialize();

    final entry = repository.getAll().single;
    expect(entry.stockName, unreadableName);
    expect(entry.message, contains(unreadableName));
    expect(entry.spokenText, contains(unreadableName));
  });
}
