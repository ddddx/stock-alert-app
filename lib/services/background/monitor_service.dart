import '../../data/models/stock_quote_snapshot.dart';
import '../../data/repositories/alert_repository.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/watchlist_repository.dart';
import '../alerts/alert_rule_engine.dart';
import '../audio/audio_alert_service.dart';
import '../market/market_data_provider.dart';
import '../platform/platform_bridge_service.dart';
import 'monitoring_policy.dart';

class MonitorRunResult {
  const MonitorRunResult({
    required this.quotes,
    required this.triggers,
    required this.checkedAt,
    required this.summary,
    this.error,
  });

  final List<StockQuoteSnapshot> quotes;
  final List<AlertTrigger> triggers;
  final DateTime checkedAt;
  final String summary;
  final String? error;

  bool get hasError => error != null;
}

abstract class MonitorService {
  Future<void> prepare();
  Future<MonitorRunResult> refreshWatchlist({
    bool forceFetch = false,
    void Function(List<StockQuoteSnapshot> quotes)? onQuotesUpdated,
  });
  Future<void> start();
  Future<void> stop();
  Future<void> reload();
  Future<void> requestBackgroundRefresh();
  bool get isRunning;
  List<StockQuoteSnapshot> get latestQuotes;
  StockQuoteSnapshot? latestQuoteFor(String code);
}

class AshareMonitorService implements MonitorService {
  AshareMonitorService({
    required WatchlistRepository watchlistRepository,
    required AlertRepository alertRepository,
    required HistoryRepository historyRepository,
    required SettingsRepository settingsRepository,
    required MarketDataProvider marketDataService,
    MarketDataProvider Function()? marketDataProviderResolver,
    required AudioAlertService audioAlertService,
    required AlertRuleEngine ruleEngine,
    required PlatformBridgeService platformBridgeService,
    AshareMarketHours marketHours = const AshareMarketHours(),
    DateTime Function()? now,
  })  : _watchlistRepository = watchlistRepository,
        _alertRepository = alertRepository,
        _historyRepository = historyRepository,
        _settingsRepository = settingsRepository,
        _marketDataService = marketDataService,
        _marketDataProviderResolver = marketDataProviderResolver,
        _audioAlertService = audioAlertService,
        _ruleEngine = ruleEngine,
        _platformBridgeService = platformBridgeService,
        _marketHours = marketHours,
        _now = now ?? DateTime.now;

  final WatchlistRepository _watchlistRepository;
  final AlertRepository _alertRepository;
  final HistoryRepository _historyRepository;
  final SettingsRepository _settingsRepository;
  final MarketDataProvider _marketDataService;
  final MarketDataProvider Function()? _marketDataProviderResolver;
  final AudioAlertService _audioAlertService;
  final AlertRuleEngine _ruleEngine;
  final PlatformBridgeService _platformBridgeService;
  final AshareMarketHours _marketHours;
  final DateTime Function() _now;

  MarketDataProvider get _resolvedMarketDataProvider =>
      _marketDataProviderResolver?.call() ?? _marketDataService;

  bool _running = false;
  List<StockQuoteSnapshot> _latestQuotes = const [];

  @override
  bool get isRunning => _running;

  @override
  List<StockQuoteSnapshot> get latestQuotes => List.unmodifiable(_latestQuotes);

  @override
  StockQuoteSnapshot? latestQuoteFor(String code) {
    for (final quote in _latestQuotes) {
      if (quote.code == code) {
        return quote;
      }
    }
    return null;
  }

  @override
  Future<void> prepare() async {
    final ready = await _audioAlertService.preload();
    if (!ready) {
      final reason = _audioAlertService.lastErrorMessage ?? '语音插件未完成初始化。';
      await _settingsRepository.markPrepared('语音播报预热失败：$reason');
      return;
    }
    await _settingsRepository.markPrepared('已完成语音播报预热，可执行A股扫描。');
  }

  @override
  Future<MonitorRunResult> refreshWatchlist({
    bool forceFetch = false,
    void Function(List<StockQuoteSnapshot> quotes)? onQuotesUpdated,
  }) async {
    final checkedAt = _now();
    final watchlist = _watchlistRepository.getAll();
    if (watchlist.isEmpty) {
      const summary = '自选为空，未执行行情刷新。';
      await _settingsRepository.markChecked(
          checkedAt: checkedAt, message: summary);
      await _platformBridgeService.updateForegroundMonitorSummary(
          summary: summary);
      return MonitorRunResult(
        quotes: const [],
        triggers: const [],
        checkedAt: checkedAt,
        summary: summary,
      );
    }

    final monitoredWatchlist = watchlist
        .where((stock) => stock.monitoringEnabled)
        .toList(growable: false);
    if (monitoredWatchlist.isEmpty) {
      const summary = '自选中暂无开启监控的股票，未执行行情刷新。';
      _latestQuotes = const [];
      await _settingsRepository.markChecked(
        checkedAt: checkedAt,
        message: summary,
      );
      await _platformBridgeService.updateForegroundMonitorSummary(
        summary: summary,
      );
      return MonitorRunResult(
        quotes: const [],
        triggers: const [],
        checkedAt: checkedAt,
        summary: summary,
      );
    }

    if (!forceFetch && !_marketHours.isTradingTime(checkedAt)) {
      final summary = _marketHours.buildClosedMessage(checkedAt);
      await _settingsRepository.markChecked(
        checkedAt: checkedAt,
        message: summary,
      );
      await _platformBridgeService.updateForegroundMonitorSummary(
        summary: summary,
      );
      return MonitorRunResult(
        quotes: _latestQuotes,
        triggers: const [],
        checkedAt: checkedAt,
        summary: summary,
      );
    }

    try {
      final latestByCode = {
        for (final quote in _latestQuotes) quote.code: quote,
      };
      final progressiveQuotes =
          await _resolvedMarketDataProvider.fetchQuotesProgressively(
        monitoredWatchlist,
        onQuoteReceived: (quote) {
          latestByCode[quote.code] = quote;
          _latestQuotes = monitoredWatchlist
              .map((stock) => latestByCode[stock.code])
              .whereType<StockQuoteSnapshot>()
              .toList(growable: false);
          onQuotesUpdated?.call(latestQuotes);
        },
      );
      final quotes = progressiveQuotes;
      _latestQuotes = quotes;
      onQuotesUpdated?.call(latestQuotes);
      final triggers = _ruleEngine.processQuotes(
        rules: _alertRepository.getEnabledRules(),
        quotes: quotes,
      );

      final soundEnabled = _settingsRepository.getStatus().soundEnabled;
      for (final trigger in triggers) {
        var playedSound = false;
        if (soundEnabled) {
          playedSound = await _audioAlertService.speak(trigger.spokenText);
        }
        await _platformBridgeService.showAlertNotification(
          title: _buildAlertNotificationTitle(trigger.quote),
          message: trigger.message,
          notificationId: _buildAlertNotificationId(trigger),
        );
        await _historyRepository
            .add(trigger.toHistoryEntry(playedSound: playedSound));
      }

      final summary = triggers.isEmpty
          ? '已刷新 ${quotes.length} 只A股，暂无规则触发。'
          : '已刷新 ${quotes.length} 只A股，触发 ${triggers.length} 条提醒。';
      await _settingsRepository.markChecked(
          checkedAt: checkedAt, message: summary);
      await _platformBridgeService.updateForegroundMonitorSummary(
          summary: summary);
      return MonitorRunResult(
        quotes: quotes,
        triggers: triggers,
        checkedAt: checkedAt,
        summary: summary,
      );
    } catch (error) {
      final summary = '行情刷新失败：$error';
      await _settingsRepository.markChecked(
          checkedAt: checkedAt, message: summary);
      await _platformBridgeService.updateForegroundMonitorSummary(
          summary: summary);
      return MonitorRunResult(
        quotes: _latestQuotes,
        triggers: const [],
        checkedAt: checkedAt,
        summary: summary,
        error: error.toString(),
      );
    }
  }

  @override
  Future<void> start() async {
    final started = await _platformBridgeService.startForegroundMonitorService(
      summary: _settingsRepository.getStatus().lastMessage,
    );
    _running = started;
    if (!started) {
      await _settingsRepository.updateService(false);
      await _settingsRepository.markChecked(
        checkedAt: _now(),
        message: '后台监控启动失败，已自动关闭后台守护，请检查通知/前台服务权限后重试。',
      );
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _platformBridgeService.stopForegroundMonitorService();
  }

  @override
  Future<void> reload() async {
    if (!_settingsRepository.getStatus().serviceEnabled) {
      _running = false;
      return;
    }
    final started =
        await _platformBridgeService.reloadForegroundMonitorService();
    _running = started;
    if (!started) {
      await _settingsRepository.updateService(false);
      await _settingsRepository.markChecked(
        checkedAt: _now(),
        message: '后台监控恢复失败，已自动关闭后台守护，请重新启用。',
      );
    }
  }

  @override
  Future<void> requestBackgroundRefresh() async {
    if (!_settingsRepository.getStatus().serviceEnabled) {
      return;
    }
    final started =
        await _platformBridgeService.refreshForegroundMonitorService();
    if (!started) {
      _running = false;
      await _settingsRepository.updateService(false);
      await _settingsRepository.markChecked(
        checkedAt: _now(),
        message: '后台监控刷新失败，已自动关闭后台守护，请重新启用。',
      );
    }
  }

  String _buildAlertNotificationTitle(StockQuoteSnapshot quote) {
    final name = quote.name.trim();
    if (name.isNotEmpty && name != quote.code) {
      return '$name ${quote.code}';
    }
    return quote.code;
  }

  int _buildAlertNotificationId(AlertTrigger trigger) {
    final seed =
        '${trigger.rule.id}:${trigger.quote.code}:${trigger.triggeredAt.millisecondsSinceEpoch}';
    return seed.hashCode & 0x7fffffff;
  }
}
