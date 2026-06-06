import '../../data/models/diagnostic_log_entry.dart';
import '../../data/models/stock_quote_snapshot.dart';
import '../../data/repositories/alert_repository.dart';
import '../../data/repositories/diagnostic_log_repository.dart';
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
    DiagnosticLogRepository diagnosticLogRepository =
        const NoopDiagnosticLogRepository(),
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
        _diagnosticLogRepository = diagnosticLogRepository,
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
  final DiagnosticLogRepository _diagnosticLogRepository;
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
      await _logDiagnostic(
        level: DiagnosticLogLevel.warning,
        category: 'speech',
        message: '语音播报预热失败：$reason',
      );
      return;
    }
    await _settingsRepository.markPrepared('已完成语音播报预热，可执行A股扫描。');
    await _logDiagnostic(
      level: DiagnosticLogLevel.info,
      category: 'speech',
      message: '语音播报预热完成。',
    );
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
      await _logDiagnostic(
        level: DiagnosticLogLevel.info,
        category: 'refresh',
        message: summary,
        timestamp: checkedAt,
      );
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
      await _logDiagnostic(
        level: DiagnosticLogLevel.warning,
        category: 'refresh',
        message: summary,
        timestamp: checkedAt,
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
      await _logDiagnostic(
        level: DiagnosticLogLevel.info,
        category: 'refresh',
        message: summary,
        timestamp: checkedAt,
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
      final refreshedByCode = <String, StockQuoteSnapshot>{};
      List<StockQuoteSnapshot> refreshedQuotesInWatchlistOrder() {
        return monitoredWatchlist
            .map((stock) => refreshedByCode[stock.code])
            .whereType<StockQuoteSnapshot>()
            .toList(growable: false);
      }

      final progressiveQuotes =
          await _resolvedMarketDataProvider.fetchQuotesProgressively(
        monitoredWatchlist,
        onQuoteReceived: (quote) {
          latestByCode[quote.code] = quote;
          refreshedByCode[quote.code] = quote;
          _latestQuotes = monitoredWatchlist
              .map((stock) => latestByCode[stock.code])
              .whereType<StockQuoteSnapshot>()
              .toList(growable: false);
          onQuotesUpdated?.call(refreshedQuotesInWatchlistOrder());
        },
      );
      final quotes = progressiveQuotes;
      _latestQuotes = quotes;
      onQuotesUpdated?.call(quotes);
      final triggers = _ruleEngine.processQuotes(
        rules: _alertRepository.getEnabledRules(),
        quotes: quotes,
        alertCooldownSeconds:
            _settingsRepository.getStatus().alertCooldownSeconds,
      );

      final soundEnabled = _settingsRepository.getStatus().soundEnabled;
      for (final trigger in triggers) {
        var playedSound = false;
        if (soundEnabled) {
          playedSound = await _audioAlertService.speak(trigger.spokenText);
          if (!playedSound) {
            await _logDiagnostic(
              level: DiagnosticLogLevel.warning,
              category: 'speech',
              message: '语音播报未成功：${trigger.quote.code} ${trigger.message}',
              timestamp: checkedAt,
            );
          }
        }
        final notificationPublished =
            await _platformBridgeService.showAlertNotification(
          title: _buildAlertNotificationTitle(trigger.quote),
          message: trigger.message,
          notificationId: _buildAlertNotificationId(trigger),
        );
        if (!notificationPublished) {
          await _logDiagnostic(
            level: DiagnosticLogLevel.warning,
            category: 'notification',
            message: '本地通知发布失败：${trigger.quote.code} ${trigger.message}',
            timestamp: checkedAt,
          );
        }
        await _historyRepository
            .add(trigger.toHistoryEntry(playedSound: playedSound));
        await _logDiagnostic(
          level: DiagnosticLogLevel.info,
          category: 'alert',
          message: '触发提醒：${trigger.message}',
          timestamp: checkedAt,
        );
      }

      final summary = triggers.isEmpty
          ? '已刷新 ${quotes.length} 只A股，暂无规则触发。'
          : '已刷新 ${quotes.length} 只A股，触发 ${triggers.length} 条提醒。';
      await _settingsRepository.markChecked(
          checkedAt: checkedAt, message: summary);
      await _platformBridgeService.updateForegroundMonitorSummary(
          summary: summary);
      await _logDiagnostic(
        level: DiagnosticLogLevel.info,
        category: 'refresh',
        message: summary,
        timestamp: checkedAt,
      );
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
      await _logDiagnostic(
        level: DiagnosticLogLevel.error,
        category: 'refresh',
        message: summary,
        timestamp: checkedAt,
      );
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
      await _logDiagnostic(
        level: DiagnosticLogLevel.error,
        category: 'service',
        message: '后台监控启动失败，已自动关闭后台守护。',
      );
      return;
    }
    await _logDiagnostic(
      level: DiagnosticLogLevel.info,
      category: 'service',
      message: '后台监控启动成功。',
    );
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _platformBridgeService.stopForegroundMonitorService();
    await _logDiagnostic(
      level: DiagnosticLogLevel.info,
      category: 'service',
      message: '后台监控守护已关闭。',
    );
  }

  @override
  Future<void> reload() async {
    if (!_settingsRepository.getStatus().serviceEnabled) {
      _running = false;
      await _logDiagnostic(
        level: DiagnosticLogLevel.info,
        category: 'service',
        message: '后台监控未开启，跳过服务恢复。',
      );
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
      await _logDiagnostic(
        level: DiagnosticLogLevel.error,
        category: 'service',
        message: '后台监控恢复失败，已自动关闭后台守护。',
      );
      return;
    }
    await _logDiagnostic(
      level: DiagnosticLogLevel.info,
      category: 'service',
      message: '后台监控恢复成功。',
    );
  }

  @override
  Future<void> requestBackgroundRefresh() async {
    if (!_settingsRepository.getStatus().serviceEnabled) {
      await _logDiagnostic(
        level: DiagnosticLogLevel.info,
        category: 'service',
        message: '后台监控未开启，跳过后台即时刷新。',
      );
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
      await _logDiagnostic(
        level: DiagnosticLogLevel.error,
        category: 'service',
        message: '后台监控即时刷新失败，已自动关闭后台守护。',
      );
      return;
    }
    await _logDiagnostic(
      level: DiagnosticLogLevel.info,
      category: 'service',
      message: '已请求后台即时刷新。',
    );
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

  Future<void> _logDiagnostic({
    required DiagnosticLogLevel level,
    required String category,
    required String message,
    DateTime? timestamp,
  }) async {
    try {
      await _diagnosticLogRepository.add(
        DiagnosticLogEntry.create(
          level: level,
          category: category,
          message: message,
          timestamp: timestamp ?? _now(),
        ),
      );
    } catch (_) {
      // Diagnostics must never break monitoring.
    }
  }
}
