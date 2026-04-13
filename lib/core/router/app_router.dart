import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/local_alert_repository.dart';
import '../../data/repositories/local_history_repository.dart';
import '../../data/repositories/local_settings_repository.dart';
import '../../data/repositories/local_watchlist_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/models/stock_quote_snapshot.dart';
import '../../data/models/app_backup_payload.dart';
import '../../features/alerts/presentation/pages/alerts_page.dart';
import '../../features/history/presentation/pages/history_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/watchlist/presentation/pages/watchlist_page.dart';
import '../../services/alerts/alert_message_builder.dart';
import '../../services/alerts/alert_rule_engine.dart';
import '../../services/audio/audio_alert_service.dart';
import '../../services/background/monitor_service.dart';
import '../../services/market/ashare_market_data_service.dart';
import '../../services/market/market_data_provider.dart';
import '../../services/market/sina_market_data_provider.dart';
import '../../services/platform/platform_bridge_service.dart';
import '../../services/storage/json_file_store.dart';
import '../../services/webdav/webdav_backup_service.dart';

Future<void> restoreBackgroundMonitorOnLaunch({
  required SettingsRepository settingsRepository,
  required MonitorService monitorService,
}) async {
  if (!settingsRepository.getStatus().serviceEnabled) {
    return;
  }
  await monitorService.reload();
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _refreshing = false;
  bool _refreshQueued = false;
  bool _queuedForceFetch = false;
  bool _bootstrapping = true;
  bool _androidOnboardingRunning = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  Timer? _foregroundRefreshTimer;
  Map<String, StockQuoteSnapshot> _progressiveQuotesByCode = const {};
  Set<String> _pendingRefreshCodes = const <String>{};

  final _platformBridgeService = PlatformBridgeService();
  final _watchlistStore = JsonFileStore(fileName: 'watchlist.json');
  final _alertStore = JsonFileStore(fileName: 'alert_rules.json');
  final _historyStore = JsonFileStore(fileName: 'alert_history.json');
  final _settingsStore = JsonFileStore(fileName: 'monitor_settings.json');
  late final _watchlistRepository =
      LocalWatchlistRepository(store: _watchlistStore);
  late final _alertRepository = LocalAlertRepository(store: _alertStore);
  late final _historyRepository = LocalHistoryRepository(store: _historyStore);
  late final _settingsRepository =
      LocalSettingsRepository(store: _settingsStore);
  late final Map<String, MarketDataProvider> _marketDataProviders = {
    AshareMarketDataService.providerIdValue: AshareMarketDataService(),
    SinaMarketDataProvider.providerIdValue: SinaMarketDataProvider(),
  };
  final _messageBuilder = AlertMessageBuilder();
  final _audioService = FlutterTtsAudioAlertService();
  final _webDavBackupService = WebDavBackupService();
  late final _ruleEngine = AlertRuleEngine(messageBuilder: _messageBuilder);
  late final _monitorService = AshareMonitorService(
    watchlistRepository: _watchlistRepository,
    alertRepository: _alertRepository,
    historyRepository: _historyRepository,
    settingsRepository: _settingsRepository,
    marketDataService: _currentMarketDataProvider,
    marketDataProviderResolver: () => _currentMarketDataProvider,
    audioAlertService: _audioService,
    ruleEngine: _ruleEngine,
    platformBridgeService: _platformBridgeService,
  );

  MarketDataProvider get _currentMarketDataProvider {
    final providerId = _settingsRepository.getStatus().marketDataProviderId;
    return _marketDataProviders[providerId] ??
        _marketDataProviders[defaultMarketDataProviderId]!;
  }

  static const List<String> _titles = ['自选', '规则', '历史', '设置'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _bootstrap();
      } finally {
        if (mounted) {
          setState(() {
            _bootstrapping = false;
          });
        }
      }
      _syncForegroundRefreshTimer();
      await _runAndroidFirstLaunchOnboarding();
      await _refreshQuotes();
    });
  }

  @override
  void dispose() {
    _foregroundRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (_bootstrapping) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        _syncForegroundRefreshTimer();
        unawaited(_handleResume());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foregroundRefreshTimer?.cancel();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      WatchlistPage(
        repository: _watchlistRepository,
        marketDataService: _currentMarketDataProvider,
        quotes: _monitorService.latestQuotes,
        quotesByCode: _progressiveQuotesByCode,
        pendingRefreshCodes: _pendingRefreshCodes,
        isRefreshing: _refreshing,
        monitorStatus: _settingsRepository.getStatus(),
        onRefresh: _refreshQuotes,
        onSortOrderChanged: (order) async {
          await _settingsRepository.updateWatchlistSortOrder(order);
          _markDirty();
        },
      ),
      AlertsPage(
        repository: _alertRepository,
        watchlistRepository: _watchlistRepository,
        quotes: _monitorService.latestQuotes,
        onRuleUpdated: (previousRule, nextRule) async {
          _ruleEngine.replaceRule(previousRule, nextRule);
        },
        onRuleDeleted: (rule) async {
          _ruleEngine.removeRule(rule.id);
        },
      ),
      HistoryPage(
        repository: _historyRepository,
        watchlistRepository: _watchlistRepository,
      ),
      SettingsPage(
        repository: _settingsRepository,
        monitorService: _monitorService,
        audioService: _audioService,
        messageBuilder: _messageBuilder,
        platformBridgeService: _platformBridgeService,
        previewQuote: _monitorService.latestQuotes.isEmpty
            ? null
            : _monitorService.latestQuotes.first,
        onRefresh: _refreshQuotes,
        onChanged: _markDirty,
        onRequestAndroidBackgroundAccess: _requestAndroidBackgroundAccess,
        onExportToWebDav: _exportToWebDav,
        onImportFromWebDav: _importFromWebDav,
        currentMarketDataProviderId:
            _settingsRepository.getStatus().marketDataProviderId,
        availableMarketDataProviders:
            _marketDataProviders.values.toList(growable: false),
        onMarketDataProviderChanged: _handleMarketDataProviderChanged,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('股票异动雷达 · ${_titles[_currentIndex]}'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _refreshQuotes,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新行情',
            ),
        ],
      ),
      body: SafeArea(
        child: _bootstrapping
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在加载本地数据与监控配置...'),
                  ],
                ),
              )
            : pages[_currentIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (_currentIndex == index) {
            return;
          }
          setState(() => _currentIndex = index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart_outlined),
            activeIcon: Icon(Icons.show_chart),
            label: '自选',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_active_outlined),
            activeIcon: Icon(Icons.notifications_active),
            label: '规则',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: '历史',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  Future<void> _bootstrap() async {
    final storagePath = await _platformBridgeService.getStorageDirectoryPath();
    await Future.wait([
      _watchlistStore.initialize(storagePath),
      _alertStore.initialize(storagePath),
      _historyStore.initialize(storagePath),
      _settingsStore.initialize(storagePath),
    ]);

    await _watchlistRepository.initialize();
    await _alertRepository.initialize();
    await _historyRepository.initialize();
    await _settingsRepository.initialize();
    await restoreBackgroundMonitorOnLaunch(
      settingsRepository: _settingsRepository,
      monitorService: _monitorService,
    );
  }

  Future<void> _runAndroidFirstLaunchOnboarding() async {
    if (_androidOnboardingRunning ||
        _settingsRepository.getStatus().androidOnboardingShown) {
      return;
    }
    _androidOnboardingRunning = true;
    try {
      await _requestAndroidBackgroundAccess(onboarding: true);
      await _settingsRepository.markAndroidOnboardingShown();
    } finally {
      _androidOnboardingRunning = false;
      _markDirty();
    }
  }

  Future<bool> _requestAndroidBackgroundAccess(
      {required bool onboarding}) async {
    final initial =
        await _platformBridgeService.getAndroidBackgroundAccessStatus();
    if (!initial.isAndroid) {
      return true;
    }

    var status = initial;

    if (status.needsNotificationPermissionRequest) {
      final shouldRequest = onboarding
          ? await _showChoiceDialog(
              title: '开启通知权限',
              message: '后台监控依赖常驻通知。请允许通知权限，安卓 13 及以上系统还需要单独授权通知。',
              confirmLabel: '去授权',
              cancelLabel: '稍后',
            )
          : true;
      if (shouldRequest) {
        await _platformBridgeService.requestNotificationPermission();
        status =
            await _platformBridgeService.getAndroidBackgroundAccessStatus();
      }
    }

    if (!status.canPostNotifications) {
      await _showActionDialog(
        title: '通知仍未开启',
        message: '后台监控的前台服务必须能正常显示通知。请先在系统通知设置中允许本应用通知，再重新开启后台监控。',
        actionLabel: '打开设置',
        onAction: _platformBridgeService.openNotificationSettings,
      );
      if (!onboarding) {
        return false;
      }
    }

    if (status.needsBatteryOptimizationGuidance) {
      await _showActionDialog(
        title: '关闭电池优化',
        message: '部分机型会因为电池优化而杀死前台服务。建议把本应用加入后台白名单，避免监控和语音播报被系统中断。',
        actionLabel: '去设置',
        onAction: _platformBridgeService.openBatteryOptimizationSettings,
      );
    }

    return status.canPostNotifications;
  }

  Future<void> _showActionDialog({
    required String title,
    required String message,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) async {
    if (!mounted) {
      return;
    }
    final shouldOpen = await _showChoiceDialog(
      title: title,
      message: message,
      confirmLabel: actionLabel,
      cancelLabel: '稍后',
    );
    if (shouldOpen) {
      await onAction();
    }
  }

  Future<bool> _showChoiceDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
  }) async {
    if (!mounted) {
      return false;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _refreshQuotes({bool forceFetch = true}) async {
    if (_bootstrapping) {
      return;
    }
    if (_refreshing) {
      _refreshQueued = true;
      _queuedForceFetch = _queuedForceFetch || forceFetch;
      return;
    }
    setState(() {
      _refreshing = true;
      _progressiveQuotesByCode = {
        for (final quote in _monitorService.latestQuotes) quote.code: quote,
      };
      _pendingRefreshCodes = _watchlistRepository
          .getAll()
          .where((stock) => stock.monitoringEnabled)
          .map((stock) => stock.code)
          .toSet();
    });
    try {
      await _monitorService.refreshWatchlist(
        forceFetch: forceFetch,
        onQuotesUpdated: (quotes) {
          if (!mounted) {
            return;
          }
          final refreshedCodes = quotes.map((quote) => quote.code).toSet();
          setState(() {
            _progressiveQuotesByCode = {
              for (final quote in quotes) quote.code: quote,
            };
            _pendingRefreshCodes = _pendingRefreshCodes
                .where((code) => !refreshedCodes.contains(code))
                .toSet();
          });
        },
      );
    } finally {
      final shouldRunAgain = _refreshQueued;
      final nextForceFetch = _queuedForceFetch;
      _refreshQueued = false;
      _queuedForceFetch = false;
      if (mounted) {
        setState(() {
          _refreshing = false;
          _progressiveQuotesByCode = {
            for (final quote in _monitorService.latestQuotes) quote.code: quote,
          };
          _pendingRefreshCodes = const <String>{};
        });
      }
      if (mounted &&
          shouldRunAgain &&
          _lifecycleState == AppLifecycleState.resumed) {
        unawaited(_refreshQuotes(forceFetch: nextForceFetch));
      }
    }
  }

  Future<String> _exportToWebDav(WebDavCredentials credentials) async {
    final status = _settingsRepository.getStatus();
    final payload = AppBackupPayload(
      schemaVersion: WebDavBackupService.schemaVersion,
      exportedAt: DateTime.now(),
      watchlist: _watchlistRepository.getAll(),
      alertRules: _alertRepository.getAll(),
      preferences: AppBackupPreferences(
        soundEnabled: status.soundEnabled,
        pollIntervalSeconds: status.pollIntervalSeconds,
        watchlistSortOrder: status.watchlistSortOrder,
        marketDataProviderId: status.marketDataProviderId,
      ),
    );
    await _webDavBackupService.exportPayload(
      credentials: credentials,
      payload: payload,
    );
    return '已导出 ${payload.watchlist.length} 只自选和 ${payload.alertRules.length} 条规则到 WebDAV。';
  }

  Future<String> _importFromWebDav(WebDavCredentials credentials) async {
    final payload = await _webDavBackupService.importPayload(
      credentials: credentials,
    );
    await _watchlistRepository.replaceAll(payload.watchlist);
    await _alertRepository.replaceAll(payload.alertRules);
    _ruleEngine.reset();
    await _settingsRepository.updateSound(payload.preferences.soundEnabled);
    await _settingsRepository.updatePollIntervalSeconds(
      payload.preferences.pollIntervalSeconds,
    );
    await _settingsRepository.updateWatchlistSortOrder(
      payload.preferences.watchlistSortOrder,
    );
    await _settingsRepository.updateMarketDataProviderId(
      payload.preferences.marketDataProviderId,
    );
    await _settingsRepository.markChecked(
      checkedAt: DateTime.now(),
      message: '已从 WebDAV 导入自选、规则和核心偏好。',
    );
    if (_settingsRepository.getStatus().serviceEnabled) {
      await _monitorService.reload();
    }
    await _refreshQuotes();
    _markDirty();
    return '已从 WebDAV 恢复 ${payload.watchlist.length} 只自选和 ${payload.alertRules.length} 条规则。';
  }

  Future<void> _handleResume() async {
    await _settingsRepository.initialize();
    await _historyRepository.initialize();
    _syncForegroundRefreshTimer();
    if (mounted) {
      setState(() {});
    }
    final status = _settingsRepository.getStatus();
    if (status.serviceEnabled) {
      return;
    }
    await _refreshQuotes(forceFetch: true);
  }

  Future<void> _handleMarketDataProviderChanged(String providerId) async {
    final currentProviderId = _settingsRepository.getStatus().marketDataProviderId;
    if (currentProviderId == providerId ||
        !_marketDataProviders.containsKey(providerId)) {
      return;
    }

    await _settingsRepository.updateMarketDataProviderId(providerId);
    if (_settingsRepository.getStatus().serviceEnabled) {
      await _monitorService.reload();
    }
    await _refreshQuotes(forceFetch: true);
    _markDirty();
  }

  void _markDirty() {
    _syncForegroundRefreshTimer();
    if (mounted) {
      setState(() {});
    }
  }

  void _syncForegroundRefreshTimer() {
    _foregroundRefreshTimer?.cancel();
    if (_bootstrapping || _lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final status = _settingsRepository.getStatus();
    if (status.serviceEnabled) {
      return;
    }

    _foregroundRefreshTimer = Timer.periodic(
      Duration(seconds: status.pollIntervalSeconds),
      (_) => unawaited(_refreshQuotes(forceFetch: false)),
    );
  }
}
