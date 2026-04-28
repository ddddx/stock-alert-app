import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/alert_history_entry.dart';
import 'package:stock_alert_app/data/models/alert_rule.dart';
import 'package:stock_alert_app/data/models/market_sentiment_snapshot.dart';
import 'package:stock_alert_app/data/models/monitor_status.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/data/models/watchlist_sort_order.dart';
import 'package:stock_alert_app/data/models/webdav_config.dart';
import 'package:stock_alert_app/data/repositories/history_repository.dart';
import 'package:stock_alert_app/data/repositories/settings_repository.dart';
import 'package:stock_alert_app/data/repositories/watchlist_repository.dart';
import 'package:stock_alert_app/services/audio/audio_alert_service.dart';
import 'package:stock_alert_app/services/background/daily_briefing_service.dart';
import 'package:stock_alert_app/data/models/stock_search_result.dart';
import 'package:stock_alert_app/services/market/market_data_provider.dart';

void main() {
  test('opening briefing runs at 9:30 and writes history once', () async {
    final watchlistRepository = _FakeWatchlistRepository([
      const StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
    ]);
    final historyRepository = _FakeHistoryRepository();
    final settingsRepository = _FakeSettingsRepository(
      const MonitorStatus(
        serviceEnabled: false,
        soundEnabled: true,
        pollIntervalSeconds: 20,
        alertCooldownSeconds: 120,
        lastCheckAt: null,
        lastMessage: 'ready',
        androidOnboardingShown: true,
        watchlistSortOrder: WatchlistSortOrder.none,
        webDavConfig: WebDavConfig(endpoint: '', username: ''),
        openingBriefingEnabled: true,
        closingReviewEnabled: false,
        lastOpeningBriefingDayKey: '',
        lastClosingReviewDayKey: '',
      ),
    );
    final audioService = _FakeAudioAlertService();
    final marketProvider = _FakeMarketDataProvider(
      quotes: [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1502,
          previousClose: 1500,
          changeAmount: 2,
          changePercent: 0.13,
          openPrice: 1505,
          highPrice: 1508,
          lowPrice: 1499,
          volume: 1200,
          timestamp: DateTime(2026, 4, 7, 9, 30),
        ),
      ],
      sentiment: MarketSentimentSnapshot(
        advancingCount: 3120,
        decliningCount: 1820,
        flatCount: 120,
        limitUpCount: 68,
        capturedAt: DateTime(2026, 4, 7, 9, 30),
      ),
    );

    final service = AshareDailyBriefingService(
      watchlistRepository: watchlistRepository,
      historyRepository: historyRepository,
      settingsRepository: settingsRepository,
      marketDataProviderResolver: () => marketProvider,
      audioAlertService: audioService,
      now: () => DateTime(2026, 4, 7, 9, 30, 1),
    );

    await service.syncNow();
    await service.syncNow();

    expect(audioService.spokenTexts, hasLength(1));
    expect(historyRepository.entries, hasLength(1));
    expect(
      historyRepository.entries.single.ruleId,
      AshareDailyBriefingService.openingBriefingRuleId,
    );
    expect(
      settingsRepository.getStatus().lastOpeningBriefingDayKey,
      '2026-04-07',
    );
  });

  test('closing review includes trigger count and played count', () async {
    final watchlistRepository = _FakeWatchlistRepository([
      const StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
      const StockIdentity(code: '000001', name: '平安银行', market: 'SZ'),
    ]);
    final historyRepository = _FakeHistoryRepository(
      entries: [
        _alertEntry(
          id: 'a1',
          ruleId: 'rule-1',
          playedSound: true,
          triggeredAt: DateTime(2026, 4, 7, 10, 0),
        ),
        _alertEntry(
          id: 'a2',
          ruleId: 'rule-2',
          playedSound: false,
          triggeredAt: DateTime(2026, 4, 7, 11, 0),
        ),
        _alertEntry(
          id: 'a3',
          ruleId: AshareDailyBriefingService.openingBriefingRuleId,
          playedSound: true,
          triggeredAt: DateTime(2026, 4, 7, 9, 30),
        ),
      ],
    );
    final settingsRepository = _FakeSettingsRepository(
      const MonitorStatus(
        serviceEnabled: false,
        soundEnabled: true,
        pollIntervalSeconds: 20,
        alertCooldownSeconds: 120,
        lastCheckAt: null,
        lastMessage: 'ready',
        androidOnboardingShown: true,
        watchlistSortOrder: WatchlistSortOrder.none,
        webDavConfig: WebDavConfig(endpoint: '', username: ''),
        openingBriefingEnabled: false,
        closingReviewEnabled: true,
        lastOpeningBriefingDayKey: '',
        lastClosingReviewDayKey: '',
      ),
    );
    final audioService = _FakeAudioAlertService();
    final marketProvider = _FakeMarketDataProvider(
      quotes: [
        StockQuoteSnapshot(
          code: '600519',
          name: '贵州茅台',
          market: 'SH',
          lastPrice: 1520,
          previousClose: 1500,
          changeAmount: 20,
          changePercent: 1.33,
          openPrice: 1505,
          highPrice: 1525,
          lowPrice: 1498,
          volume: 1800,
          timestamp: DateTime(2026, 4, 7, 15, 0),
        ),
        StockQuoteSnapshot(
          code: '000001',
          name: '平安银行',
          market: 'SZ',
          lastPrice: 10.0,
          previousClose: 10.5,
          changeAmount: -0.5,
          changePercent: -4.76,
          openPrice: 10.4,
          highPrice: 10.5,
          lowPrice: 9.95,
          volume: 2000,
          timestamp: DateTime(2026, 4, 7, 15, 0),
        ),
      ],
      sentiment: MarketSentimentSnapshot(
        advancingCount: 0,
        decliningCount: 0,
        flatCount: 0,
        limitUpCount: 0,
        capturedAt: DateTime(2026, 4, 7, 15, 0),
      ),
    );

    final service = AshareDailyBriefingService(
      watchlistRepository: watchlistRepository,
      historyRepository: historyRepository,
      settingsRepository: settingsRepository,
      marketDataProviderResolver: () => marketProvider,
      audioAlertService: audioService,
      now: () => DateTime(2026, 4, 7, 15, 5, 0),
    );

    await service.syncNow();

    final closingEntry = historyRepository.entries.first;
    expect(
      closingEntry.ruleId,
      AshareDailyBriefingService.closingReviewRuleId,
    );
    expect(closingEntry.message, contains('今日触发提醒2次'));
    expect(closingEntry.message, contains('语音播报成功1次'));
    expect(
      settingsRepository.getStatus().lastClosingReviewDayKey,
      '2026-04-07',
    );
  });
}

AlertHistoryEntry _alertEntry({
  required String id,
  required String ruleId,
  required bool playedSound,
  required DateTime triggeredAt,
}) {
  return AlertHistoryEntry(
    id: id,
    ruleId: ruleId,
    ruleType: AlertRuleType.shortWindowMove,
    stockCode: '600519',
    stockName: '贵州茅台',
    market: 'SH',
    triggeredAt: triggeredAt,
    currentPrice: 1500,
    referencePrice: 1490,
    changeAmount: 10,
    changePercent: 0.67,
    message: 'msg',
    spokenText: 'speak',
    playedSound: playedSound,
  );
}

class _FakeMarketDataProvider extends MarketDataProvider {
  _FakeMarketDataProvider({
    required this.quotes,
    required this.sentiment,
  });

  final List<StockQuoteSnapshot> quotes;
  final MarketSentimentSnapshot sentiment;

  @override
  String get providerId => 'fake';

  @override
  String get providerName => 'fake';

  @override
  Future<StockQuoteSnapshot> fetchQuote(StockIdentity stock) async {
    return quotes.firstWhere((item) => item.code == stock.code);
  }

  @override
  Future<List<StockQuoteSnapshot>> fetchQuotes(
    List<StockIdentity> stocks, {
    bool preferSingleQuoteRetrieval = false,
  }) async {
    return stocks
        .map((stock) => quotes.firstWhere((item) => item.code == stock.code))
        .toList(growable: false);
  }

  @override
  Future<MarketSentimentSnapshot> fetchMarketSentiment() async {
    return sentiment;
  }

  @override
  Future<List<StockSearchResult>> searchStocks(String keyword) async {
    return const [];
  }
}

class _FakeAudioAlertService implements AudioAlertService {
  final List<String> spokenTexts = <String>[];

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

class _FakeWatchlistRepository implements WatchlistRepository {
  _FakeWatchlistRepository(this._stocks);

  final List<StockIdentity> _stocks;

  @override
  Future<void> initialize() async {}

  @override
  List<StockIdentity> getAll() => List.unmodifiable(_stocks);

  @override
  bool contains(String code) => _stocks.any((s) => s.code == code);

  @override
  Future<bool> add(StockIdentity stock) async => true;

  @override
  Future<void> remove(String code) async {}

  @override
  Future<void> move({
    required int fromIndex,
    required int toIndex,
  }) async {}

  @override
  Future<void> updateMonitoring(String code, bool enabled) async {}

  @override
  Future<void> updateMonitoringEnabled(String code, bool enabled) async {}

  @override
  Future<void> replaceAll(List<StockIdentity> stocks) async {}
}

class _FakeHistoryRepository implements HistoryRepository {
  _FakeHistoryRepository({List<AlertHistoryEntry> entries = const []})
      : entries = List<AlertHistoryEntry>.from(entries);

  final List<AlertHistoryEntry> entries;

  @override
  Future<void> initialize() async {}

  @override
  List<AlertHistoryEntry> getAll() => List.unmodifiable(entries);

  @override
  Future<void> add(AlertHistoryEntry entry) async {
    entries.insert(0, entry);
  }
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._status);

  MonitorStatus _status;

  @override
  Future<void> initialize() async {}

  @override
  MonitorStatus getStatus() => _status;

  @override
  Future<void> markAndroidOnboardingShown() async {}

  @override
  Future<void> markChecked({
    required DateTime checkedAt,
    required String message,
  }) async {}

  @override
  Future<void> markPrepared(String message) async {}

  @override
  Future<void> updateAlertCooldownSeconds(int seconds) async {}

  @override
  Future<void> updateMarketDataProviderId(String providerId) async {}

  @override
  Future<void> updatePollIntervalSeconds(int seconds) async {}

  @override
  Future<void> updateService(bool enabled) async {}

  @override
  Future<void> updateSound(bool enabled) async {}

  @override
  Future<void> updateWebDavConfig(WebDavConfig config) async {}

  @override
  Future<void> updateWatchlistSortOrder(WatchlistSortOrder order) async {}

  @override
  Future<void> updateOpeningBriefing(bool enabled) async {
    _status = _status.copyWith(openingBriefingEnabled: enabled);
  }

  @override
  Future<void> updateClosingReview(bool enabled) async {
    _status = _status.copyWith(closingReviewEnabled: enabled);
  }

  @override
  Future<void> markOpeningBriefingBroadcasted(String tradingDayKey) async {
    _status = _status.copyWith(lastOpeningBriefingDayKey: tradingDayKey);
  }

  @override
  Future<void> markClosingReviewBroadcasted(String tradingDayKey) async {
    _status = _status.copyWith(lastClosingReviewDayKey: tradingDayKey);
  }
}
