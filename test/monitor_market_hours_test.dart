import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/alert_history_entry.dart';
import 'package:stock_alert_app/data/models/alert_rule.dart';
import 'package:stock_alert_app/data/models/monitor_status.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/data/models/watchlist_sort_order.dart';
import 'package:stock_alert_app/data/models/webdav_config.dart';
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
  test('monitor refresh skips quote fetching during the midday break',
      () async {
    final marketDataService = _RecordingMarketDataService();
    final service = AshareMonitorService(
      watchlistRepository: const _FakeWatchlistRepository(),
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
    expect(result.summary, isNotEmpty);
    expect(result.summary, contains('13:00'));
  });

  test('monitor refresh fetches quotes during A-share trading hours', () async {
    final marketDataService = _RecordingMarketDataService();
    final service = AshareMonitorService(
      watchlistRepository: const _FakeWatchlistRepository(),
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
    expect(marketDataService.lastRequestedCodes, ['600519']);
    expect(result.summary, isNotEmpty);
    expect(result.summary, isNot(contains('13:00')));
  });

  test('monitor refresh filters out stocks with monitoring disabled', () async {
    final marketDataService = _RecordingMarketDataService();
    final service = AshareMonitorService(
      watchlistRepository: const _FakeWatchlistRepository(
        items: [
          StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
          StockIdentity(
            code: '000001',
            name: '平安银行',
            market: 'SZ',
            monitoringEnabled: false,
          ),
        ],
      ),
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
    expect(marketDataService.lastRequestedCodes, ['600519']);
    expect(result.summary, contains('1 只A股'));
  });

  test('forced watchlist refresh fetches quotes outside trading hours',
      () async {
    final marketDataService = _RecordingMarketDataService();
    final service = AshareMonitorService(
      watchlistRepository: const _FakeWatchlistRepository(),
      alertRepository: _FakeAlertRepository(),
      historyRepository: _FakeHistoryRepository(),
      settingsRepository: _FakeSettingsRepository(),
      marketDataService: marketDataService,
      audioAlertService: _FakeAudioAlertService(),
      ruleEngine: AlertRuleEngine(messageBuilder: AlertMessageBuilder()),
      platformBridgeService: _FakePlatformBridgeService(),
      now: () => DateTime(2026, 3, 23, 12, 0),
    );

    final result = await service.refreshWatchlist(forceFetch: true);

    expect(marketDataService.fetchQuotesCalls, 1);
    expect(result.quotes, hasLength(1));
    expect(service.latestQuotes, hasLength(1));
    expect(result.hasError, isFalse);
  });

  test('monitor refresh records alerts without speech when sound is disabled',
      () async {
    final historyRepository = _FakeHistoryRepository();
    final settingsRepository = _FakeSettingsRepository(soundEnabled: false);
    final audioAlertService = _FakeAudioAlertService();
    final marketDataService = _SequenceMarketDataService([
      [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1500,
          previousClose: 1490,
          changeAmount: 3,
          changePercent: 0.2,
          openPrice: 1492,
          highPrice: 1500,
          lowPrice: 1490,
          volume: 1000,
          timestamp: DateTime(2026, 3, 23, 10, 0),
        ),
      ],
      [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1502,
          previousClose: 1490,
          changeAmount: 12,
          changePercent: 0.8,
          openPrice: 1492,
          highPrice: 1502,
          lowPrice: 1490,
          volume: 1100,
          timestamp: DateTime(2026, 3, 23, 10, 1),
        ),
      ],
    ]);
    final service = AshareMonitorService(
      watchlistRepository: const _FakeWatchlistRepository(),
      alertRepository: _FakeAlertRepository(
        rules: [
          AlertRule.stepAlert(
            id: 'rule-step',
            stockCode: '600519',
            stockName: '贵州茅台',
            market: 'SH',
            stepValue: 0.5,
            stepMetric: StepMetric.percent,
            enabled: true,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      ),
      historyRepository: historyRepository,
      settingsRepository: settingsRepository,
      marketDataService: marketDataService,
      audioAlertService: audioAlertService,
      ruleEngine: AlertRuleEngine(messageBuilder: AlertMessageBuilder()),
      platformBridgeService: _FakePlatformBridgeService(),
      now: () => DateTime(2026, 3, 23, 10, 0),
    );

    await service.refreshWatchlist();
    final result = await service.refreshWatchlist();

    expect(result.triggers, hasLength(1));
    expect(audioAlertService.spokenTexts, isEmpty);
    expect(historyRepository.entries, hasLength(1));
    expect(historyRepository.entries.single.playedSound, isFalse);
  });

  test('monitor refresh publishes a local alert notification on trigger',
      () async {
    final historyRepository = _FakeHistoryRepository();
    final settingsRepository = _FakeSettingsRepository(soundEnabled: false);
    final platformBridgeService = _FakePlatformBridgeService();
    final marketDataService = _SequenceMarketDataService([
      [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1500,
          previousClose: 1490,
          changeAmount: 3,
          changePercent: 0.2,
          openPrice: 1492,
          highPrice: 1500,
          lowPrice: 1490,
          volume: 1000,
          timestamp: DateTime(2026, 3, 23, 10, 0),
        ),
      ],
      [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1502,
          previousClose: 1490,
          changeAmount: 12,
          changePercent: 0.8,
          openPrice: 1492,
          highPrice: 1502,
          lowPrice: 1490,
          volume: 1100,
          timestamp: DateTime(2026, 3, 23, 10, 1),
        ),
      ],
    ]);
    final service = AshareMonitorService(
      watchlistRepository: const _FakeWatchlistRepository(),
      alertRepository: _FakeAlertRepository(
        rules: [
          AlertRule.stepAlert(
            id: 'rule-step',
            stockCode: '600519',
            stockName: '贵州茅台',
            market: 'SH',
            stepValue: 0.5,
            stepMetric: StepMetric.percent,
            enabled: true,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      ),
      historyRepository: historyRepository,
      settingsRepository: settingsRepository,
      marketDataService: marketDataService,
      audioAlertService: _FakeAudioAlertService(),
      ruleEngine: AlertRuleEngine(messageBuilder: AlertMessageBuilder()),
      platformBridgeService: platformBridgeService,
      now: () => DateTime(2026, 3, 23, 10, 0),
    );

    await service.refreshWatchlist();
    final result = await service.refreshWatchlist();

    expect(result.triggers, hasLength(1));
    expect(historyRepository.entries, hasLength(1));
    expect(platformBridgeService.alertNotifications, hasLength(1));
    expect(platformBridgeService.alertNotifications.single.title,
        contains('600519'));
    expect(platformBridgeService.alertNotifications.single.message,
        contains('阶梯提醒'));
  });

  test('monitor refresh enforces alert cooldown for repeated triggers',
      () async {
    final historyRepository = _FakeHistoryRepository();
    final settingsRepository = _FakeSettingsRepository(
      soundEnabled: false,
      alertCooldownSeconds: 120,
    );
    final marketDataService = _SequenceMarketDataService([
      [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1500,
          previousClose: 1490,
          changeAmount: 3,
          changePercent: 0.2,
          openPrice: 1492,
          highPrice: 1500,
          lowPrice: 1490,
          volume: 1000,
          timestamp: DateTime(2026, 3, 23, 10, 0),
        ),
      ],
      [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1502,
          previousClose: 1490,
          changeAmount: 12,
          changePercent: 0.8,
          openPrice: 1492,
          highPrice: 1502,
          lowPrice: 1490,
          volume: 1100,
          timestamp: DateTime(2026, 3, 23, 10, 1),
        ),
      ],
      [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1510,
          previousClose: 1490,
          changeAmount: 20,
          changePercent: 1.34,
          openPrice: 1492,
          highPrice: 1510,
          lowPrice: 1490,
          volume: 1500,
          timestamp: DateTime(2026, 3, 23, 10, 2),
        ),
      ],
    ]);
    final service = AshareMonitorService(
      watchlistRepository: const _FakeWatchlistRepository(),
      alertRepository: _FakeAlertRepository(
        rules: [
          AlertRule.stepAlert(
            id: 'rule-step',
            stockCode: '600519',
            stockName: '贵州茅台',
            market: 'SH',
            stepValue: 0.5,
            stepMetric: StepMetric.percent,
            enabled: true,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      ),
      historyRepository: historyRepository,
      settingsRepository: settingsRepository,
      marketDataService: marketDataService,
      audioAlertService: _FakeAudioAlertService(),
      ruleEngine: AlertRuleEngine(messageBuilder: AlertMessageBuilder()),
      platformBridgeService: _FakePlatformBridgeService(),
      now: () => DateTime(2026, 3, 23, 10, 0),
    );

    await service.refreshWatchlist();
    final firstTrigger = await service.refreshWatchlist();
    final secondTrigger = await service.refreshWatchlist();

    expect(firstTrigger.triggers, hasLength(1));
    expect(secondTrigger.triggers, isEmpty);
    expect(historyRepository.entries, hasLength(1));
  });

  test(
      'monitor refresh keeps partial quotes when one fallback stock still fails',
      () async {
    final settingsRepository = _FakeSettingsRepository();
    final marketDataService = AshareMarketDataService(
      sleeper: (_) async {},
      jsonLoader: (uri) async {
        if (uri.toString().contains('ulist.np/get')) {
          return {
            'data': {
              'diff': [
                {
                  'f12': '600519',
                  'f14': 'Moutai',
                  'f18': 149000,
                  'f43': '-',
                  'f169': '-',
                  'f170': '-',
                  'f46': '-',
                  'f44': '-',
                  'f45': '-',
                  'f47': '-',
                  'f59': 2,
                },
                {
                  'f12': '000001',
                  'f14': 'Ping An Bank',
                  'f18': 1000,
                  'f43': '-',
                  'f169': '-',
                  'f170': '-',
                  'f46': '-',
                  'f44': '-',
                  'f45': '-',
                  'f47': '-',
                  'f59': 2,
                },
              ],
            },
          };
        }

        if (uri.toString().contains('secid=1.600519')) {
          return {
            'data': {
              'f57': '600519',
              'f58': 'Moutai',
              'f59': 2,
              'f43': 150000,
              'f169': 1000,
              'f170': 67,
              'f46': 149200,
              'f44': 150000,
              'f45': 149000,
              'f47': 1000,
              'f60': 149000,
              'f18': 149000,
            },
          };
        }

        if (uri.toString().contains('secid=0.000001')) {
          throw const SocketException('Connection reset by peer');
        }

        throw StateError('unexpected uri: $uri');
      },
      textLoader: (uri) async {
        throw const SocketException('Connection reset by peer');
      },
    );
    final service = AshareMonitorService(
      watchlistRepository: const _FakeWatchlistRepository(
        items: [
          StockIdentity(code: '600519', name: 'Moutai', market: 'SH'),
          StockIdentity(code: '000001', name: 'Ping An Bank', market: 'SZ'),
        ],
      ),
      alertRepository: _FakeAlertRepository(),
      historyRepository: _FakeHistoryRepository(),
      settingsRepository: settingsRepository,
      marketDataService: marketDataService,
      audioAlertService: _FakeAudioAlertService(),
      ruleEngine: AlertRuleEngine(messageBuilder: AlertMessageBuilder()),
      platformBridgeService: _FakePlatformBridgeService(),
      now: () => DateTime(2026, 3, 23, 10, 0),
    );

    final result = await service.refreshWatchlist();

    expect(result.hasError, isFalse);
    expect(result.triggers, isEmpty);
    expect(result.quotes, hasLength(1));
    expect(result.quotes.single.code, '600519');
    expect(service.latestQuotes, hasLength(1));
    expect(service.latestQuoteFor('600519'), isNotNull);
    expect(service.latestQuoteFor('000001'), isNull);
    expect(settingsRepository.getStatus().lastMessage, result.summary);
  });
}

class _RecordingMarketDataService extends AshareMarketDataService {
  int fetchQuotesCalls = 0;
  List<String> lastRequestedCodes = const [];

  List<StockQuoteSnapshot> _fakeQuotes() {
    return [
      StockQuoteSnapshot(
        code: '600519',
        name: '璐靛窞鑼呭彴',
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

  @override
  Future<List<StockQuoteSnapshot>> fetchQuotesProgressively(
    List<StockIdentity> watchlist, {
    void Function(StockQuoteSnapshot quote)? onQuoteReceived,
    bool preferSingleQuoteRetrieval = false,
  }) async {
    fetchQuotesCalls += 1;
    lastRequestedCodes = watchlist.map((item) => item.code).toList();
    final quotes = _fakeQuotes();
    for (final quote in quotes) {
      onQuoteReceived?.call(quote);
    }
    return quotes;
  }

  @override
  Future<List<StockQuoteSnapshot>> fetchQuotes(List<StockIdentity> watchlist,
      {bool preferSingleQuoteRetrieval = false}) async {
    return fetchQuotesProgressively(
      watchlist,
      preferSingleQuoteRetrieval: preferSingleQuoteRetrieval,
    );
  }
}

class _SequenceMarketDataService extends AshareMarketDataService {
  _SequenceMarketDataService(this._quotesByCall);

  final List<List<StockQuoteSnapshot>> _quotesByCall;
  int _callIndex = 0;

  @override
  Future<List<StockQuoteSnapshot>> fetchQuotesProgressively(
    List<StockIdentity> watchlist, {
    void Function(StockQuoteSnapshot quote)? onQuoteReceived,
    bool preferSingleQuoteRetrieval = false,
  }) async {
    final quotes = _quotesByCall[_callIndex.clamp(0, _quotesByCall.length - 1)];
    if (_callIndex < _quotesByCall.length - 1) {
      _callIndex += 1;
    }
    for (final quote in quotes) {
      onQuoteReceived?.call(quote);
    }
    return quotes;
  }

  @override
  Future<List<StockQuoteSnapshot>> fetchQuotes(
    List<StockIdentity> watchlist, {
    bool preferSingleQuoteRetrieval = false,
  }) async {
    return fetchQuotesProgressively(
      watchlist,
      preferSingleQuoteRetrieval: preferSingleQuoteRetrieval,
    );
  }
}

class _FakeWatchlistRepository implements WatchlistRepository {
  const _FakeWatchlistRepository({
    this.items = const [
      StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
    ],
  });

  final List<StockIdentity> items;

  @override
  Future<bool> add(StockIdentity stock) async => true;

  @override
  bool contains(String code) => items.any((item) => item.code == code);

  @override
  List<StockIdentity> getAll() => items;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> remove(String code) async {}

  @override
  Future<void> replaceAll(List<StockIdentity> stocks) async {}

  @override
  Future<void> updateMonitoringEnabled(String code, bool enabled) async {}
}

class _FakeAlertRepository implements AlertRepository {
  _FakeAlertRepository({this.rules = const []});

  final List<AlertRule> rules;

  @override
  Future<void> add(AlertRule rule) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  List<AlertRule> getAll() => rules;

  @override
  List<AlertRule> getEnabledRules() =>
      rules.where((rule) => rule.enabled).toList(growable: false);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> update(AlertRule rule) async {}

  @override
  Future<void> toggle(String id, bool enabled) async {}

  @override
  Future<void> replaceAll(List<AlertRule> rules) async {}
}

class _FakeHistoryRepository implements HistoryRepository {
  final List<AlertHistoryEntry> entries = [];

  @override
  Future<void> add(AlertHistoryEntry entry) async {
    entries.add(entry);
  }

  @override
  List<AlertHistoryEntry> getAll() => List.unmodifiable(entries);

  @override
  Future<void> initialize() async {}
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({
    bool serviceEnabled = false,
    bool soundEnabled = true,
    int alertCooldownSeconds = 120,
  }) : _status = MonitorStatus(
          serviceEnabled: serviceEnabled,
          soundEnabled: soundEnabled,
          pollIntervalSeconds: 5,
          alertCooldownSeconds: alertCooldownSeconds,
          lastCheckAt: null,
          lastMessage: 'ready',
          androidOnboardingShown: false,
          watchlistSortOrder: WatchlistSortOrder.none,
          webDavConfig: const WebDavConfig(endpoint: '', username: ''),
        );

  MonitorStatus _status;

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
  Future<void> updateAlertCooldownSeconds(int seconds) async {
    _status = _status.copyWith(alertCooldownSeconds: seconds);
  }

  @override
  Future<void> updateMarketDataProviderId(String providerId) async {
    _status = _status.copyWith(marketDataProviderId: providerId);
  }

  @override
  Future<void> updateWatchlistSortOrder(WatchlistSortOrder order) async {
    _status = _status.copyWith(watchlistSortOrder: order);
  }

  @override
  Future<void> updateWebDavConfig(WebDavConfig config) async {
    _status = _status.copyWith(webDavConfig: config);
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
  final List<String> spokenTexts = [];

  @override
  String? get lastErrorMessage => null;

  @override
  Future<bool> preload() async => true;

  @override
  Future<bool> speak(String text) async {
    spokenTexts.add(text);
    return true;
  }
}

class _FakePlatformBridgeService extends PlatformBridgeService {
  final List<_AlertNotificationRecord> alertNotifications = [];

  @override
  Future<void> updateForegroundMonitorSummary(
      {required String summary}) async {}

  @override
  Future<bool> showAlertNotification({
    required String title,
    required String message,
    required int notificationId,
  }) async {
    alertNotifications.add(
      _AlertNotificationRecord(
        title: title,
        message: message,
        notificationId: notificationId,
      ),
    );
    return true;
  }
}

class _AlertNotificationRecord {
  const _AlertNotificationRecord({
    required this.title,
    required this.message,
    required this.notificationId,
  });

  final String title;
  final String message;
  final int notificationId;
}
