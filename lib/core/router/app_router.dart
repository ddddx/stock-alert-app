import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/local_alert_repository.dart';
import '../../data/repositories/local_history_repository.dart';
import '../../data/repositories/local_settings_repository.dart';
import '../../data/repositories/local_watchlist_repository.dart';
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

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  bool _refreshing = false;
  bool _bootstrapping = true;

  final _platformBridgeService = PlatformBridgeService();
  final _watchlistStore = JsonFileStore(fileName: 'watchlist.json');
  final _alertStore = JsonFileStore(fileName: 'alert_rules.json');
  final _historyStore = JsonFileStore(fileName: 'alert_history.json');
  final _settingsStore = JsonFileStore(fileName: 'monitor_settings.json');
  late final _watchlistRepository = LocalWatchlistRepository(store: _watchlistStore);
  late final _alertRepository = LocalAlertRepository(store: _alertStore);
  late final _historyRepository = LocalHistoryRepository(store: _historyStore);
  late final _settingsRepository = LocalSettingsRepository(store: _settingsStore);
  final _marketDataService = AshareMarketDataService();
  final _messageBuilder = AlertMessageBuilder();
  final _audioService = PlatformTtsAudioAlertService();
  late final _monitorService = AshareMonitorService(
    watchlistRepository: _watchlistRepository,
    alertRepository: _alertRepository,
    historyRepository: _historyRepository,
    settingsRepository: _settingsRepository,
    marketDataService: _marketDataService,
    audioAlertService: _audioService,
    ruleEngine: AlertRuleEngine(messageBuilder: _messageBuilder),
    platformBridgeService: _platformBridgeService,
  );

  static const List<String> _titles = ['自选', '规则', '历史', '设置'];

  @override
  void initState() {
    super.initState();
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
      await _refreshQuotes();
    });
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
    await _monitorService.prepare();
    if (_settingsRepository.getStatus().serviceEnabled) {
      await _monitorService.start();
    }
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

  void _markDirty() {
    if (mounted) {
      setState(() {});
    }
  }
}
