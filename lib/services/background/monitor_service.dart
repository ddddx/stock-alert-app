import '../../data/models/stock_quote_snapshot.dart';
import '../../data/repositories/alert_repository.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/watchlist_repository.dart';
import '../alerts/alert_rule_engine.dart';
import '../audio/audio_alert_service.dart';
import '../market/ashare_market_data_service.dart';
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
  Future<MonitorRunResult> refreshWatchlist();
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
    required AshareMarketDataService marketDataService,
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
        _audioAlertService = audioAlertService,
        _ruleEngine = ruleEngine,
        _platformBridgeService = platformBridgeService,
        _marketHours = marketHours,
        _now = now ?? DateTime.now;

  final WatchlistRepository _watchlistRepository;
  final AlertRepository _alertRepository;
  final HistoryRepository _historyRepository;
  final SettingsRepository _settingsRepository;
  final AshareMarketDataService _marketDataService;
  final AudioAlertService _audioAlertService;
  final AlertRuleEngine _ruleEngine;
  final PlatformBridgeService _platformBridgeService;
  final AshareMarketHours _marketHours;
  final DateTime Function() _now;

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
    await _settingsRepository.markPrepared('已完成语音播报预热，可执行 A 股扫描。');
  }

  @override
  Future<MonitorRunResult> refreshWatchlist() async {
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

    if (!_marketHours.isTradingTime(checkedAt)) {
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
      final quotes = await _marketDataService.fetchQuotes(watchlist);
      _latestQuotes = quotes;
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
        await _historyRepository
            .add(trigger.toHistoryEntry(playedSound: playedSound));
      }

      final summary = triggers.isEmpty
          ? '已刷新 ${quotes.length} 只 A 股，暂无规则触发。'
          : '已刷新 ${quotes.length} 只 A 股，触发 ${triggers.length} 条提醒。';
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
}
