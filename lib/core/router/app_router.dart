import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/local_alert_repository.dart';
import '../../data/repositories/local_history_repository.dart';
import '../../data/repositories/local_settings_repository.dart';
import '../../data/repositories/local_watchlist_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../features/alerts/presentation/pages/alerts_page.dart';
import '../../features/history/presentation/pages/history_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/watchlist/presentation/pages/watchlist_page.dart';
import '../../services/alerts/alert_message_builder.dart';
import '../../services/alerts/alert_rule_engine.dart';
import '../../services/audio/audio_alert_service.dart';
import '../../services/background/monitor_service.dart';
import '../../services/market/ashare_market_data_service.dart';
import '../../services/platform/platform_bridge_service.dart';
import '../../services/storage/json_file_store.dart';

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
  bool _bootstrapping = true;
  bool _androidOnboardingRunning = false;

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
  final _marketDataService = AshareMarketDataService();
  final _messageBuilder = AlertMessageBuilder();
  final _audioService = FlutterTtsAudioAlertService();
  late final _ruleEngine = AlertRuleEngine(messageBuilder: _messageBuilder);
  late final _monitorService = AshareMonitorService(
    watchlistRepository: _watchlistRepository,
    alertRepository: _alertRepository,
    historyRepository: _historyRepository,
    settingsRepository: _settingsRepository,
    marketDataService: _marketDataService,
    audioAlertService: _audioService,
    ruleEngine: _ruleEngine,
    platformBridgeService: _platformBridgeService,
  );

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
      await _runAndroidFirstLaunchOnboarding();
      await _refreshQuotes();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_bootstrapping) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_handleResume());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      WatchlistPage(
        repository: _watchlistRepository,
        marketDataService: _marketDataService,
        quotes: _monitorService.latestQuotes,
        onRefresh: _refreshQuotes,
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
      HistoryPage(repository: _historyRepository),
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

  Future<bool> _requestAndroidBackgroundAccess({required bool onboarding}) async {
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
              message:
                  '后台监控依赖常驻通知。请允许通知权限，Android 13 及以上还需要显式授权 POST_NOTIFICATIONS。',
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
        message:
            '后台监控的前台服务必须能正常显示通知。请在系统通知设置中允许本应用通知后，再重新开启后台监控。',
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
        message:
            '部分机型会因为电池优化而杀死前台服务。建议把本应用加入后台白名单，避免监控和语音播报被系统中断。',
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

  Future<void> _refreshQuotes() async {
    if (_refreshing || _bootstrapping) {
      return;
    }
    setState(() {
      _refreshing = true;
    });
    await _monitorService.refreshWatchlist();
    if (!mounted) {
      return;
    }
    setState(() {
      _refreshing = false;
    });
  }

  Future<void> _handleResume() async {
    await _settingsRepository.initialize();
    await _historyRepository.initialize();
    if (mounted) {
      setState(() {});
    }
  }

  void _markDirty() {
    if (mounted) {
      setState(() {});
    }
  }
}
