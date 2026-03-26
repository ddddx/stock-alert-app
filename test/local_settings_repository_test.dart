import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/repositories/local_settings_repository.dart';
import 'package:stock_alert_app/services/storage/json_file_store.dart';

void main() {
  test('initialize preserves valid poll intervals below 15 seconds', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-settings-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'monitor_settings.json');
    await store.initialize(directory.path);
    await store.writeJson({
      'serviceEnabled': false,
      'soundEnabled': true,
      'pollIntervalSeconds': 5,
      'lastMessage': 'ready',
      'androidOnboardingShown': false,
    });

    final repository = LocalSettingsRepository(store: store);
    await repository.initialize();

    expect(repository.getStatus().pollIntervalSeconds, 5);
  });

  test('update clamps poll interval to the new one-second minimum', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-settings-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'monitor_settings.json');
    await store.initialize(directory.path);
    final repository = LocalSettingsRepository(store: store);
    await repository.initialize();

    await repository.updatePollIntervalSeconds(0);

    expect(repository.getStatus().pollIntervalSeconds, 1);
  });
}
