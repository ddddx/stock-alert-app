import 'package:flutter_test/flutter_test.dart';
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
  test('monitor refresh skips quote fetching during the midday break', () async {
    final marketDataService = _RecordingMarketDataService();
    final service = AshareMonitorService(
      watchlistRepository: _FakeWatchlistRepository(),
      alertRepository: _FakeAlertRepository(),
      historyRepository: _FakeHistoryRepository(),
      settingsRepository: _FakeSettingsRepository(),
      marketDataService: marketDataService,
      audioAlertService: _FakeAudioAlertService(),
      ruleEngine: AlertRuleEngine(messageBuilder: AlertMessageBuilder()),
      platformBridgeService: _FakePlatformBridgeService(),
      now: () => DateTime(2026, 3, 23, 12, 0),
    );

    final result = await service.refreshWatchlist();

    expect(marketDataService.fetchQuotesCalls, 0);
    expect(result.triggers, isEmpty);
    expect(result.summary, contains('Monitoring paused'));
    expect(result.summary, contains('13:00'));
  });

  test('monitor refresh fetches quotes during A-share trading hours', () async {
    final marketDataService = _RecordingMarketDataService();
    final service = AshareMonitorService(
      watchlistRepository: _FakeWatchlistRepository(),
      alertRepository: _FakeAlertRepository(),
      historyRepository: _FakeHistoryRepository(),
      settingsRepository: _FakeSettingsRepository(),
      marketDataService: marketDataService,
      audioAlertService: _FakeAudioAlertService(),
      ruleEngine: AlertRuleEngine(messageBuilder: AlertMessageBuilder()),
      platformBridgeService: _FakePlatformBridgeService(),
      now: () => DateTime(2026, 3, 23, 10, 0),
    );

    final result = await service.refreshWatchlist();

    expect(marketDataService.fetchQuotesCalls, 1);
    expect(result.summary, isNot(contains('Monitoring paused')));
  });
}

class _RecordingMarketDataService extends AshareMarketDataService {
  int fetchQuotesCalls = 0;

  @override
  Future<List<StockQuoteSnapshot>> fetchQuotes(
    List<StockIdentity> watchlist,
  ) async {
    fetchQuotesCalls += 1;
    return [
      StockQuoteSnapshot(
        code: '600519',
        name: '贵州茅台',
        market: 'SH',
        lastPrice: 1500,
        previousClose: 1490,
        changeAmount: 10,
        changePercent: 0.67,
        openPrice: 1492,
        highPrice: 1500,
        lowPrice: 1490,
        volume: 1000,
        timestamp: DateTime(2026, 3, 23, 10, 0),
      ),
    ];
  }
}

class _FakeWatchlistRepository implements WatchlistRepository {
  @override
  Future<bool> add(StockIdentity stock) async => true;

  @override
  bool contains(String code) => code == '600519';

  @override
  List<StockIdentity> getAll() => const [
        StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
      ];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> remove(String code) async {}
}

class _FakeAlertRepository implements AlertRepository {
  @override
  Future<void> add(AlertRule rule) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  List<AlertRule> getAll() => const [];

  @override
  List<AlertRule> getEnabledRules() => const [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> update(AlertRule rule) async {}

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

class _FakeSettingsRepository implements SettingsRepository {
  MonitorStatus _status = const MonitorStatus(
    serviceEnabled: false,
    soundEnabled: true,
    pollIntervalSeconds: 5,
    lastCheckAt: null,
    lastMessage: 'ready',
    androidOnboardingShown: false,
  );

  @override
  MonitorStatus getStatus() => _status;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> markAndroidOnboardingShown() async {
    _status = _status.copyWith(androidOnboardingShown: true);
  }

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

class _FakeAudioAlertService implements AudioAlertService {
  @override
  String? get lastErrorMessage => null;

  @override
  Future<bool> preload() async => true;

  @override
  Future<bool> speak(String text) async => true;
}

class _FakePlatformBridgeService extends PlatformBridgeService {
  @override
  Future<void> updateForegroundMonitorSummary({required String summary}) async {}
}
