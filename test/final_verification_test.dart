import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/monitor_status.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/data/models/stock_search_result.dart';
import 'package:stock_alert_app/data/models/watchlist_sort_order.dart';
import 'package:stock_alert_app/data/models/webdav_config.dart';
import 'package:stock_alert_app/data/repositories/settings_repository.dart';
import 'package:stock_alert_app/data/repositories/watchlist_repository.dart';
import 'package:stock_alert_app/features/settings/presentation/pages/settings_page.dart';
import 'package:stock_alert_app/features/watchlist/presentation/pages/watchlist_page.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';
import 'package:stock_alert_app/services/audio/audio_alert_service.dart';
import 'package:stock_alert_app/services/background/monitor_service.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';
import 'package:stock_alert_app/services/platform/platform_bridge_service.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('search sheet triggers search after typing', (tester) async {
    final marketDataService = _FakeMarketDataService();
    final watchlistRepository = _FakeWatchlistRepository();
    final settingsRepository = _FakeSettingsRepository();

    await tester.pumpWidget(
      buildTestApp(
        WatchlistPage(
          repository: watchlistRepository,
          marketDataService: marketDataService,
          quotes: const [],
          monitorStatus: settingsRepository.getStatus(),
          onRefresh: () async {},
          onSortOrderChanged: (_) async {},
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
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settingsRepository = _FakeSettingsRepository();
    final audioService = _FakeAudioAlertService(shouldSucceed: true);

    await tester.pumpWidget(
      buildTestApp(
        SettingsPage(
          repository: settingsRepository,
          monitorService: _FakeMonitorService(),
          audioService: audioService,
          messageBuilder: AlertMessageBuilder(),
          platformBridgeService: _FakePlatformBridgeService(),
          previewQuote: _sampleQuote(),
          onRefresh: () async {},
          onChanged: () {},
          onRequestAndroidBackgroundAccess: ({required onboarding}) async =>
              true,
          onExportToWebDav: (_) async => 'ok',
          onImportFromWebDav: (_) async => 'ok',
        ),
      ),
    );

    final previewButton = find.text('试播真实文案');
    await tester.scrollUntilVisible(
      previewButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(audioService.preloadCalls, 1);
    expect(audioService.spokenTexts, hasLength(1));
    expect(find.textContaining('已试播：'), findsWidgets);
  });

  testWidgets('preview playback shows failure feedback', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settingsRepository = _FakeSettingsRepository();
    final audioService = _FakeAudioAlertService(shouldSucceed: false);

    await tester.pumpWidget(
      buildTestApp(
        SettingsPage(
          repository: settingsRepository,
          monitorService: _FakeMonitorService(),
          audioService: audioService,
          messageBuilder: AlertMessageBuilder(),
          platformBridgeService: _FakePlatformBridgeService(),
          previewQuote: _sampleQuote(),
          onRefresh: () async {},
          onChanged: () {},
          onRequestAndroidBackgroundAccess: ({required onboarding}) async =>
              true,
          onExportToWebDav: (_) async => 'ok',
          onImportFromWebDav: (_) async => 'ok',
        ),
      ),
    );

    final previewButton = find.text('试播真实文案');
    await tester.scrollUntilVisible(
      previewButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(audioService.preloadCalls, 1);
    expect(audioService.spokenTexts, hasLength(1));
    expect(find.textContaining('试播失败'), findsWidgets);
  });

  testWidgets('background toggle waits for Android access preflight', (
    tester,
  ) async {
    final settingsRepository = _FakeSettingsRepository();
    final monitorService = _FakeMonitorService();
    var preflightCalls = 0;

    await tester.pumpWidget(
      buildTestApp(
        SettingsPage(
          repository: settingsRepository,
          monitorService: monitorService,
          audioService: _FakeAudioAlertService(shouldSucceed: true),
          messageBuilder: AlertMessageBuilder(),
          platformBridgeService: _FakePlatformBridgeService(),
          previewQuote: _sampleQuote(),
          onRefresh: () async {},
          onChanged: () {},
          onRequestAndroidBackgroundAccess: ({required onboarding}) async {
            preflightCalls += 1;
            return false;
          },
          onExportToWebDav: (_) async => 'ok',
          onImportFromWebDav: (_) async => 'ok',
        ),
      ),
    );

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(preflightCalls, 1);
    expect(monitorService.startCalls, 0);
    expect(settingsRepository.getStatus().serviceEnabled, isFalse);
  });

  testWidgets('settings page accepts poll intervals below 15 seconds', (
    tester,
  ) async {
    final settingsRepository = _FakeSettingsRepository();
    final monitorService = _FakeMonitorService();

    await tester.pumpWidget(
      buildTestApp(
        SettingsPage(
          repository: settingsRepository,
          monitorService: monitorService,
          audioService: _FakeAudioAlertService(shouldSucceed: true),
          messageBuilder: AlertMessageBuilder(),
          platformBridgeService: _FakePlatformBridgeService(),
          previewQuote: _sampleQuote(),
          onRefresh: () async {},
          onChanged: () {},
          onRequestAndroidBackgroundAccess: ({required onboarding}) async =>
              true,
          onExportToWebDav: (_) async => 'ok',
          onImportFromWebDav: (_) async => 'ok',
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('poll-interval-input')), '5');
    await tester.tap(find.text('应用间隔'));
    await tester.pumpAndSettle();

    expect(settingsRepository.getStatus().pollIntervalSeconds, 5);
    expect(find.textContaining('5 秒'), findsWidgets);
  });

  testWidgets('settings page quick poll interval chip updates setting', (
    tester,
  ) async {
    final settingsRepository = _FakeSettingsRepository();
    final monitorService = _FakeMonitorService();

    await tester.pumpWidget(
      buildTestApp(
        SettingsPage(
          repository: settingsRepository,
          monitorService: monitorService,
          audioService: _FakeAudioAlertService(shouldSucceed: true),
          messageBuilder: AlertMessageBuilder(),
          platformBridgeService: _FakePlatformBridgeService(),
          previewQuote: _sampleQuote(),
          onRefresh: () async {},
          onChanged: () {},
          onRequestAndroidBackgroundAccess: ({required onboarding}) async =>
              true,
          onExportToWebDav: (_) async => 'ok',
          onImportFromWebDav: (_) async => 'ok',
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, '30 秒'));
    await tester.pumpAndSettle();

    expect(settingsRepository.getStatus().pollIntervalSeconds, 30);
    expect(find.textContaining('30 秒'), findsWidgets);
  });

  testWidgets('manual refresh shows foreground-only feedback when guard is off',
      (
    tester,
  ) async {
    final settingsRepository = _FakeSettingsRepository();
    final monitorService = _FakeMonitorService();

    await tester.pumpWidget(
      buildTestApp(
        SettingsPage(
          repository: settingsRepository,
          monitorService: monitorService,
          audioService: _FakeAudioAlertService(shouldSucceed: true),
          messageBuilder: AlertMessageBuilder(),
          platformBridgeService: _FakePlatformBridgeService(),
          previewQuote: _sampleQuote(),
          onRefresh: () async {},
          onChanged: () {},
          onRequestAndroidBackgroundAccess: ({required onboarding}) async =>
              true,
          onExportToWebDav: (_) async => 'ok',
          onImportFromWebDav: (_) async => 'ok',
        ),
      ),
    );

    await tester.tap(find.text('立即刷新'));
    await tester.pumpAndSettle();

    expect(monitorService.backgroundRefreshCalls, 0);
    expect(find.textContaining('已执行一次前台刷新'), findsWidgets);
  });

  testWidgets('manual refresh keeps background polling active when guard is on',
      (
    tester,
  ) async {
    final settingsRepository = _FakeSettingsRepository();
    await settingsRepository.updateService(true);
    final monitorService = _FakeMonitorService();

    await tester.pumpWidget(
      buildTestApp(
        SettingsPage(
          repository: settingsRepository,
          monitorService: monitorService,
          audioService: _FakeAudioAlertService(shouldSucceed: true),
          messageBuilder: AlertMessageBuilder(),
          platformBridgeService: _FakePlatformBridgeService(),
          previewQuote: _sampleQuote(),
          onRefresh: () async {},
          onChanged: () {},
          onRequestAndroidBackgroundAccess: ({required onboarding}) async =>
              true,
          onExportToWebDav: (_) async => 'ok',
          onImportFromWebDav: (_) async => 'ok',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('立即刷新'));
    await tester.pumpAndSettle();

    expect(monitorService.backgroundRefreshCalls, 0);
    expect(find.textContaining('后台轮询仍会按既定间隔持续运行'), findsWidgets);
  });

  testWidgets('poll preset updates interval and current summary together', (
    tester,
  ) async {
    final settingsRepository = _FakeSettingsRepository();
    await settingsRepository.updateService(true);
    final monitorService = _FakeMonitorService();

    await tester.pumpWidget(
      buildTestApp(
        SettingsPage(
          repository: settingsRepository,
          monitorService: monitorService,
          audioService: _FakeAudioAlertService(shouldSucceed: true),
          messageBuilder: AlertMessageBuilder(),
          platformBridgeService: _FakePlatformBridgeService(),
          previewQuote: _sampleQuote(),
          onRefresh: () async {},
          onChanged: () {},
          onRequestAndroidBackgroundAccess: ({required onboarding}) async =>
              true,
          onExportToWebDav: (_) async => 'ok',
          onImportFromWebDav: (_) async => 'ok',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '5 秒'));
    await tester.pumpAndSettle();

    expect(settingsRepository.getStatus().pollIntervalSeconds, 5);
    expect(monitorService.reloadCalls, 1);
    expect(find.textContaining('后台轮询间隔已更新为 5 秒'), findsWidgets);
  });

  testWidgets('webdav draft survives rebuild before save', (tester) async {
    final settingsRepository = _FakeSettingsRepository();

    await tester.pumpWidget(
      buildTestApp(
        SettingsPage(
          repository: settingsRepository,
          monitorService: _FakeMonitorService(),
          audioService: _FakeAudioAlertService(shouldSucceed: true),
          messageBuilder: AlertMessageBuilder(),
          platformBridgeService: _FakePlatformBridgeService(),
          previewQuote: _sampleQuote(),
          onRefresh: () async {},
          onChanged: () {},
          onRequestAndroidBackgroundAccess: ({required onboarding}) async =>
              true,
          onExportToWebDav: (_) async => 'ok',
          onImportFromWebDav: (_) async => 'ok',
        ),
      ),
    );

    final endpointField = find.byKey(const Key('webdav-endpoint-input'));
    final usernameField = find.byKey(const Key('webdav-username-input'));
    final exportButton = find.text('导出到 WebDAV');

    await tester.scrollUntilVisible(
      endpointField,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
        endpointField, 'https://dav.example.com/backup.json');
    await tester.enterText(usernameField, 'alice');

    await tester.tap(exportButton.first);
    await tester.pumpAndSettle();

    expect(find.text('https://dav.example.com/backup.json'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(settingsRepository.getStatus().webDavConfig.endpoint, isEmpty);
    expect(settingsRepository.getStatus().webDavConfig.username, isEmpty);
  });

  test('flutter TTS preload returns plugin setup result', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'awaitSpeakCompletion') {
        expect(call.arguments, true);
        return false;
      }
      fail('Unexpected method: ${call.method}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final service = FlutterTtsAudioAlertService();
    expect(await service.preload(), isFalse);
  });

  test('flutter TTS speak short-circuits when plugin preload fails', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var speakCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'awaitSpeakCompletion') {
        return false;
      }
      if (call.method == 'speak') {
        speakCalled = true;
        return 1;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final service = FlutterTtsAudioAlertService();
    expect(await service.speak('preview text'), isFalse);
    expect(speakCalled, isFalse);
  });

  test('flutter TTS speak returns plugin playback result', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'awaitSpeakCompletion') {
        return true;
      }
      if (call.method == 'stop') {
        return 1;
      }
      if (call.method == 'speak') {
        expect(call.arguments, 'preview text');
        return false;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final service = FlutterTtsAudioAlertService();
    expect(await service.speak('  preview text  '), isFalse);
    expect(methods, ['awaitSpeakCompletion', 'stop', 'speak']);
  });

  test('flutter TTS preload is cached after a successful setup', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var preloadCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'awaitSpeakCompletion') {
        preloadCalls += 1;
        return 1;
      }
      fail('Unexpected method: ${call.method}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final service = FlutterTtsAudioAlertService();
    expect(await service.preload(), isTrue);
    expect(await service.preload(), isTrue);
    expect(preloadCalls, 1);
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

  @override
  Future<void> replaceAll(List<StockIdentity> stocks) async {
    _items
      ..clear()
      ..addAll(stocks);
  }

  @override
  Future<void> updateMonitoringEnabled(String code, bool enabled) async {
    final index = _items.indexWhere((item) => item.code == code);
    if (index < 0) {
      return;
    }
    _items[index] = _items[index].copyWith(monitoringEnabled: enabled);
  }
}

class _FakeMarketDataService extends AshareMarketDataService {
  _FakeMarketDataService();

  final List<String> searchCalls = [];

  @override
  Future<List<StockQuoteSnapshot>> fetchQuotesProgressively(
    List<StockIdentity> stocks, {
    void Function(StockQuoteSnapshot quote)? onQuoteReceived,
    bool preferSingleQuoteRetrieval = false,
  }) async {
    return const [];
  }

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
    androidOnboardingShown: false,
    watchlistSortOrder: WatchlistSortOrder.none,
    webDavConfig: WebDavConfig(endpoint: '', username: ''),
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
  _FakeAudioAlertService({
    required this.shouldSucceed,
  });

  final bool shouldSucceed;
  int preloadCalls = 0;
  final List<String> spokenTexts = [];

  @override
  String? get lastErrorMessage => null;

  @override
  Future<bool> preload() async {
    preloadCalls += 1;
    return true;
  }

  @override
  Future<bool> speak(String text) async {
    preloadCalls += 1;
    spokenTexts.add(text);
    return shouldSucceed;
  }
}

class _FakeMonitorService implements MonitorService {
  int startCalls = 0;
  int reloadCalls = 0;
  int backgroundRefreshCalls = 0;

  @override
  bool get isRunning => false;

  @override
  List<StockQuoteSnapshot> get latestQuotes => const [];

  @override
  StockQuoteSnapshot? latestQuoteFor(String code) => null;

  @override
  Future<void> prepare() async {}

  @override
  Future<MonitorRunResult> refreshWatchlist({
    bool forceFetch = false,
    void Function(List<StockQuoteSnapshot> quotes)? onQuotesUpdated,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> reload() async {
    reloadCalls += 1;
  }

  @override
  Future<void> requestBackgroundRefresh() async {
    backgroundRefreshCalls += 1;
  }

  @override
  Future<void> start() async {
    startCalls += 1;
  }

  @override
  Future<void> stop() async {}
}

class _FakePlatformBridgeService extends PlatformBridgeService {
  _FakePlatformBridgeService();

  @override
  Future<bool> startForegroundMonitorService({required String summary}) async {
    return true;
  }

  @override
  Future<bool> reloadForegroundMonitorService() async {
    return true;
  }
}

StockQuoteSnapshot _sampleQuote() {
  return StockQuoteSnapshot(
    code: '161226',
    name: '国泰中证',
    market: 'SZ',
    securityTypeName: 'ETF',
    priceDecimalDigits: 3,
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
