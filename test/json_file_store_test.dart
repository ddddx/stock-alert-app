import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/services/storage/json_file_store.dart';

void main() {
  test('readObject restores from backup when primary file is corrupted',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-json-store-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'settings.json');
    await store.initialize(directory.path);
    await store.writeJson({
      'version': 1,
      'enabled': true,
    });
    await store.writeJson({
      'version': 2,
      'enabled': false,
    });

    final file =
        File('${directory.path}${Platform.pathSeparator}settings.json');
    await file.writeAsString('{broken-json', flush: true);

    final restored = await store.readObject();

    expect(restored, isNotNull);
    expect(restored!['version'], 2);
    expect(restored['enabled'], isFalse);

    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['version'], 2);
  });

  test('readObject returns null when both primary and backup are missing',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-json-store-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'settings.json');
    await store.initialize(directory.path);

    final result = await store.readObject();
    expect(result, isNull);
  });

  test('readList returns null when corrupted file has no backup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'stock-alert-json-store-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = JsonFileStore(fileName: 'history.json');
    await store.initialize(directory.path);
    final file = File('${directory.path}${Platform.pathSeparator}history.json');
    await file.writeAsString('{broken-json', flush: true);

    final result = await store.readList();
    expect(result, isNull);
  });
}
