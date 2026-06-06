import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/diagnostic_log_entry.dart';
import 'package:stock_alert_app/data/repositories/local_diagnostic_log_repository.dart';
import 'package:stock_alert_app/services/storage/json_file_store.dart';

void main() {
  test(
      'diagnostic repository loads, sorts, trims, persists, and clears entries',
      () async {
    final root = await Directory.systemTemp.createTemp('diagnostic_repo_test_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'diagnostic_log.json');
    await store.initialize(root.path);
    await store.writeJson([
      {
        'id': 'old',
        'timestamp': DateTime(2026, 3, 23, 9, 30).toIso8601String(),
        'level': 'info',
        'category': 'refresh',
        'message': 'old refresh',
      },
      {
        'id': 'new',
        'timestamp': DateTime(2026, 3, 23, 9, 35).toIso8601String(),
        'level': 'warning',
        'category': 'speech',
        'message': 'new speech',
      },
    ]);

    final repository = LocalDiagnosticLogRepository(
      store: store,
      maxEntries: 2,
    );
    await repository.initialize();

    expect(repository.getAll().map((entry) => entry.id), ['new', 'old']);

    await repository.add(
      DiagnosticLogEntry.create(
        level: DiagnosticLogLevel.error,
        category: 'service',
        message: 'startup failed',
        timestamp: DateTime(2026, 3, 23, 9, 40),
      ),
    );

    expect(repository.getAll(), hasLength(2));
    expect(repository.getAll().first.message, 'startup failed');
    expect(repository.getAll().last.message, 'new speech');

    final reloaded = LocalDiagnosticLogRepository(
      store: store,
      maxEntries: 2,
    );
    await reloaded.initialize();
    expect(reloaded.getAll().map((entry) => entry.message), [
      'startup failed',
      'new speech',
    ]);

    await reloaded.add(
      DiagnosticLogEntry.create(
        level: DiagnosticLogLevel.info,
        category: 'refresh',
        message: '   ',
        timestamp: DateTime(2026, 3, 23, 9, 45),
      ),
    );
    expect(reloaded.getAll(), hasLength(2));

    await reloaded.clear();
    expect(reloaded.getAll(), isEmpty);

    final cleared = LocalDiagnosticLogRepository(store: store);
    await cleared.initialize();
    expect(cleared.getAll(), isEmpty);
  });
}
