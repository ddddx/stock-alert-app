import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/monitor_status.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/data/models/stock_search_result.dart';
import 'package:stock_alert_app/data/repositories/settings_repository.dart';
import 'package:stock_alert_app/data/repositories/watchlist_repository.dart';
import 'package:stock_alert_app/features/settings/presentation/pages/settings_page.dart';
import 'package:stock_alert_app/features/watchlist/presentation/pages/watchlist_page.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';
import 'package:stock_alert_app/services/audio/audio_alert_service.dart';
import 'package:stock_alert_app/services/background/monitor_service.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';
import 'package:stock_alert_app/services/platform/platform_bridge_service.dart';

void main() {
  testWidgets('search sheet triggers search after typing', (tester) async {
    final marketDataService = _FakeMarketDataService();
    final watchlistRepository = _FakeWatchlistRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WatchlistPage(
            repository: watchlistRepository,
            marketDataService: marketDataService,
            quotes: const [],
            onRefresh: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '161226');
    await tester.pump(const Duration(milliseconds: 200));
    expect(marketDataService.searchCalls, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(marketDataService.searchCalls, ['161226']);
    expect(find.textContaining('161226'), findsWidgets);
  });

  testWidgets('preview playback shows success feedback', (tester) async {
    final settingsRepository = _FakeSettingsRepository();
    final audioService = _FakeAudioAlertService(shouldSucceed: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            repository: settingsRepository,
            monitorService: _FakeMonitorService(),
            audioService: audioService,
            messageBuilder: AlertMessageBuilder(),
            platformBridgeService: _FakePlatformBridgeService(),
            previewQuote: _sampleQuote(),
            onRefresh: () async {},
            onChanged: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pumpAndSettle();

    expect(audioService.preloadCalls, 1);
    expect(audioService.spokenTexts, hasLength(1));
    expect(find.textContaining('已试播：'), findsWidgets);
  });

  testWidgets('preview playback shows failure feedback', (tester) async {
    final settingsRepository = _FakeSettingsRepository();
    final audioService = _FakeAudioAlertService(shouldSucceed: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            repository: settingsRepository,
            monitorService: _FakeMonitorService(),
            audioService: audioService,
            messageBuilder: AlertMessageBuilder(),
            platformBridgeService: _FakePlatformBridgeService(),
            previewQuote: _sampleQuote(),
            onRefresh: () async {},
            onChanged: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pumpAndSettle();

    expect(audioService.preloadCalls, 1);
    expect(audioService.spokenTexts, hasLength(1));
    expect(find.textContaining('试播失败：'), findsWidgets);
  });
}

class _FakeWatchlistRepository implements WatchlistRepository {
  final List<StockIdentity> _items = [];

  @override
  Future<bool> add(StockIdentity stock) async {
    _items.add(stock);
    return true;
  }

  @override
  bool contains(String code) => _items.any((item) => item.code == code);

  @override
  List<StockIdentity> getAll() => List.unmodifiable(_items);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> remove(String code) async {
    _items.removeWhere((item) => item.code == code);
  }
}

class _FakeMarketDataService extends AshareMarketDataService {
  _FakeMarketDataService();

  final List<String> searchCalls = [];

  @override
  Future<List<StockSearchResult>> searchStocks(String keyword) async {
    searchCalls.add(keyword);
    return const [
      StockSearchResult(
        code: '161226',
        name: '国泰中证',
        market: 'SZ',
        securityTypeName: 'ETF',
      ),
    ];
  }
}

class _FakeSettingsRepository implements SettingsRepository {
  MonitorStatus _status = const MonitorStatus(
    serviceEnabled: false,
    soundEnabled: true,
    pollIntervalSeconds: 20,
    lastCheckAt: null,
    lastMessage: 'ready',
  );

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

class _FakeAudioAlertService implements AudioAlertService {
  _FakeAudioAlertService({required this.shouldSucceed});

  final bool shouldSucceed;
  int preloadCalls = 0;
  final List<String> spokenTexts = [];

  @override
  Future<bool> preload() async {
    preloadCalls += 1;
    return true;
  }

  @override
  Future<bool> speak(String text) async {
    spokenTexts.add(text);
    return shouldSucceed;
  }
}

class _FakeMonitorService implements MonitorService {
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
  Future<void> reload() async {}

  @override
  Future<void> requestBackgroundRefresh() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _FakePlatformBridgeService extends PlatformBridgeService {}

StockQuoteSnapshot _sampleQuote() {
  return StockQuoteSnapshot(
    code: '161226',
    name: '国泰中证',
    market: 'SZ',
    securityTypeName: 'ETF',
    lastPrice: 1.234,
    previousClose: 1.2,
    changeAmount: 0.034,
    changePercent: 2.83,
    openPrice: 1.2,
    highPrice: 1.25,
    lowPrice: 1.19,
    volume: 100000,
    timestamp: DateTime(2026, 3, 25, 9, 30),
  );
}
