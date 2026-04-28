import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/alert_rule.dart';
import 'package:stock_alert_app/data/models/app_backup_payload.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/watchlist_sort_order.dart';
import 'package:stock_alert_app/services/webdav/webdav_backup_service.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('exports payload via authenticated PUT request', () async {
    var method = '';
    String? authHeader;
    String? requestBody;

    server.listen((request) async {
      method = request.method;
      authHeader = request.headers.value(HttpHeaders.authorizationHeader);
      requestBody = await utf8.decoder.bind(request).join();
      request.response.statusCode = HttpStatus.created;
      await request.response.close();
    });

    final service = WebDavBackupService();
    await service.exportPayload(
      credentials: WebDavCredentials(
        endpoint: _endpoint(server),
        username: 'alice',
        password: 'secret',
      ),
      payload: _samplePayload(),
    );

    expect(method, 'PUT');
    expect(
      authHeader,
      'Basic ${base64Encode(utf8.encode('alice:secret'))}',
    );
    final decoded = jsonDecode(requestBody!) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], 1);
    expect((decoded['watchlist'] as List).length, 2);
    expect(
      ((decoded['watchlist'] as List)[1]
          as Map<String, dynamic>)['monitoringEnabled'],
      false,
    );
    expect((decoded['alertRules'] as List).length, 1);
  });

  test('imports payload from authenticated GET request', () async {
    final payload = _samplePayload();

    server.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      request.response.write(jsonEncode(payload.toJson()));
      await request.response.close();
    });

    final service = WebDavBackupService();
    final imported = await service.importPayload(
      credentials: WebDavCredentials(
        endpoint: _endpoint(server),
        username: 'alice',
        password: 'secret',
      ),
    );

    expect(imported.watchlist.map((item) => item.code), ['600519', '000001']);
    expect(imported.watchlist.last.monitoringEnabled, isFalse);
    expect(imported.alertRules.single.type, AlertRuleType.shortWindowMove);
    expect(imported.preferences.alertCooldownSeconds, 90);
    expect(imported.preferences.watchlistSortOrder,
        WatchlistSortOrder.changePercentDesc);
  });
}

String _endpoint(HttpServer server) {
  return 'http://${server.address.host}:${server.port}/backup.json';
}

AppBackupPayload _samplePayload() {
  return AppBackupPayload(
    schemaVersion: WebDavBackupService.schemaVersion,
    exportedAt: DateTime(2026, 3, 29, 2),
    watchlist: const [
      StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
      StockIdentity(
        code: '000001',
        name: '平安银行',
        market: 'SZ',
        monitoringEnabled: false,
      ),
    ],
    alertRules: [
      AlertRule.shortWindowMove(
        id: 'rule-1',
        stockCode: '600519',
        stockName: '贵州茅台',
        market: 'SH',
        moveThresholdPercent: 1.20,
        lookbackMinutes: 5,
        moveDirection: MoveDirection.up,
        enabled: true,
        createdAt: DateTime(2026, 3, 28),
      ),
    ],
    preferences: const AppBackupPreferences(
      soundEnabled: true,
      pollIntervalSeconds: 15,
      alertCooldownSeconds: 90,
      watchlistSortOrder: WatchlistSortOrder.changePercentDesc,
    ),
  );
}
