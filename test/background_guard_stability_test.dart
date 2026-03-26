import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/core/router/app_router.dart';
import 'package:stock_alert_app/data/models/alert_history_entry.dart';
import 'package:stock_alert_app/data/models/alert_rule.dart';
import 'package:stock_alert_app/data/models/monitor_status.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/data/repositories/alert_repository.dart';
import 'package:stock_alert_app/data/repositories/history_repository.dart';
import 'package:stock_alert_app/data/repositories/settings_repository.dart';
import 'package:stock_alert_app/data/repositories/watchlist_repository.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';
import 'package:stock_alert_app/services/alerts/alert_rule_engine.dart';
import 'package:stock_alert_app/services/audio/audio_alert_service.dart';
import 'package:stock_alert_app/services/background/monitor_service.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';
import 'package:stock_alert_app/services/platform/platform_bridge_service.dart';

void main() {
  test('startup restores background monitor when guard was previously enabled',
      () async {
    final settingsRepository = _FakeSettingsRepository(serviceEnabled: true);
    final monitorService = _RecordingMonitorService();

    await restoreBackgroundMonitorOnLaunch(
      settingsRepository: settingsRepository,
      monitorService: monitorService,
    );

    expect(monitorService.reloadCalls, 1);
  });

  test('startup skips reload when background guard is disabled', () async {
    final settingsRepository = _FakeSettingsRepository(serviceEnabled: false);
    final monitorService = _RecordingMonitorService();

    await restoreBackgroundMonitorOnLaunch(
      settingsRepository: settingsRepository,
      monitorService: monitorService,
    );

    expect(monitorService.reloadCalls, 0);
  });

  test('monitor start failure disables guard and records a readable message',
      () async {
    final settingsRepository = _FakeSettingsRepository(serviceEnabled: true);
    final service = AshareMonitorService(
      watchlistRepository: _FakeWatchlistRepository(),
      alertRepository: _FakeAlertRepository(),
      historyRepository: _FakeHistoryRepository(),
      settingsRepository: settingsRepository,
      marketDataService: AshareMarketDataService(),
      audioAlertService: _FakeAudioAlertService(),
      ruleEngine: AlertRuleEngine(messageBuilder: AlertMessageBuilder()),
      platformBridgeService: _FakePlatformBridgeService(startResult: false),
    );

    await service.start();

    expect(service.isRunning, isFalse);
    expect(settingsRepository.getStatus().serviceEnabled, isFalse);
    expect(settingsRepository.getStatus().lastMessage, contains('后台监控启动失败'));
  });

  test('monitor reload failure disables guard and records recovery failure',
      () async {
    final settingsRepository = _FakeSettingsRepository(serviceEnabled: true);
    final service = AshareMonitorService(
      watchlistRepository: _FakeWatchlistRepository(),
      alertRepository: _FakeAlertRepository(),
      historyRepository: _FakeHistoryRepository(),
      settingsRepository: settingsRepository,
      marketDataService: AshareMarketDataService(),
      audioAlertService: _FakeAudioAlertService(),
      ruleEngine: AlertRuleEngine(messageBuilder: AlertMessageBuilder()),
      platformBridgeService: _FakePlatformBridgeService(reloadResult: false),
    );

    await service.reload();

    expect(service.isRunning, isFalse);
    expect(settingsRepository.getStatus().serviceEnabled, isFalse);
    expect(settingsRepository.getStatus().lastMessage, contains('后台监控恢复失败'));
  });
}

class _RecordingMonitorService implements MonitorService {
  int reloadCalls = 0;

  @override
  bool get isRunning => false;

  @override
  List<StockQuoteSnapshot> get latestQuotes => const [];

  @override
  StockQuoteSnapshot? latestQuoteFor(String code) => null;

  @override
  Future<void> prepare() async {}

  @override
  Future<MonitorRunResult> refreshWatchlist() {
    throw UnimplementedError();
  }

  @override
  Future<void> reload() async {
    reloadCalls += 1;
  }

  @override
  Future<void> requestBackgroundRefresh() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({required bool serviceEnabled})
      : _status = MonitorStatus(
          serviceEnabled: serviceEnabled,
          soundEnabled: true,
          pollIntervalSeconds: 20,
          lastCheckAt: null,
          lastMessage: 'ready',
        );

  MonitorStatus _status;

  @override
  MonitorStatus getStatus() => _status;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> markChecked({
    required DateTime checkedAt,
    required String message,
  }) async {
    _status = _status.copyWith(lastCheckAt: checkedAt, lastMessage: message);
  }

  @override
  Future<void> markPrepared(String message) async {
    _status = _status.copyWith(lastMessage: message);
  }

  @override
  Future<void> updatePollIntervalSeconds(int seconds) async {
    _status = _status.copyWith(pollIntervalSeconds: seconds);
  }

  @override
  Future<void> updateService(bool enabled) async {
    _status = _status.copyWith(serviceEnabled: enabled);
  }

  @override
  Future<void> updateSound(bool enabled) async {
    _status = _status.copyWith(soundEnabled: enabled);
  }
}

class _FakePlatformBridgeService extends PlatformBridgeService {
  _FakePlatformBridgeService({
    this.startResult = true,
    this.reloadResult = true,
  });

  final bool startResult;
  final bool reloadResult;

  @override
  Future<bool> startForegroundMonitorService({required String summary}) async {
    return startResult;
  }

  @override
  Future<bool> reloadForegroundMonitorService() async {
    return reloadResult;
  }
}

class _FakeAudioAlertService implements AudioAlertService {
  @override
  Future<bool> preload() async => true;

  @override
  Future<bool> speak(String text) async => true;
}

class _FakeWatchlistRepository implements WatchlistRepository {
  @override
  Future<bool> add(StockIdentity stock) async => true;

  @override
  bool contains(String code) => false;

  @override
  List<StockIdentity> getAll() => const [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> remove(String code) async {}
}

class _FakeAlertRepository implements AlertRepository {
  @override
  Future<void> add(AlertRule rule) async {}

  @override
  List<AlertRule> getAll() => const [];

  @override
  List<AlertRule> getEnabledRules() => const [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> toggle(String id, bool enabled) async {}
}

class _FakeHistoryRepository implements HistoryRepository {
  @override
  Future<void> add(AlertHistoryEntry entry) async {}

  @override
  List<AlertHistoryEntry> getAll() => const [];

  @override
  Future<void> initialize() async {}
}
