import '../../data/models/stock_quote_snapshot.dart';
import '../../data/repositories/in_memory_alert_repository.dart';
import '../../data/repositories/in_memory_history_repository.dart';
import '../../data/repositories/in_memory_settings_repository.dart';
import '../../data/repositories/in_memory_watchlist_repository.dart';
import '../alerts/alert_rule_engine.dart';
import '../audio/audio_alert_service.dart';
import '../market/ashare_market_data_service.dart';

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
  bool get isRunning;
  List<StockQuoteSnapshot> get latestQuotes;
  StockQuoteSnapshot? latestQuoteFor(String code);
}

class AshareMonitorService implements MonitorService {
  AshareMonitorService({
    required InMemoryWatchlistRepository watchlistRepository,
    required InMemoryAlertRepository alertRepository,
    required InMemoryHistoryRepository historyRepository,
    required InMemorySettingsRepository settingsRepository,
    required AshareMarketDataService marketDataService,
    required AudioAlertService audioAlertService,
    required AlertRuleEngine ruleEngine,
  })  : _watchlistRepository = watchlistRepository,
        _alertRepository = alertRepository,
        _historyRepository = historyRepository,
        _settingsRepository = settingsRepository,
        _marketDataService = marketDataService,
        _audioAlertService = audioAlertService,
        _ruleEngine = ruleEngine;

  final InMemoryWatchlistRepository _watchlistRepository;
  final InMemoryAlertRepository _alertRepository;
  final InMemoryHistoryRepository _historyRepository;
  final InMemorySettingsRepository _settingsRepository;
  final AshareMarketDataService _marketDataService;
  final AudioAlertService _audioAlertService;
  final AlertRuleEngine _ruleEngine;

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
    await _audioAlertService.preload();
    _settingsRepository.markPrepared('已完成语音播报预热，可执行 A 股扫描。');
  }

  @override
  Future<MonitorRunResult> refreshWatchlist() async {
    final checkedAt = DateTime.now();
    final watchlist = _watchlistRepository.getAll();
    if (watchlist.isEmpty) {
      const summary = '自选为空，未执行行情刷新。';
      _settingsRepository.markChecked(checkedAt: checkedAt, message: summary);
      return MonitorRunResult(
        quotes: const [],
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
        _historyRepository.add(trigger.toHistoryEntry(playedSound: playedSound));
      }

      final summary = triggers.isEmpty
          ? '已刷新 ${quotes.length} 只 A 股，暂无规则触发。'
          : '已刷新 ${quotes.length} 只 A 股，触发 ${triggers.length} 条提醒。';
      _settingsRepository.markChecked(checkedAt: checkedAt, message: summary);
      return MonitorRunResult(
        quotes: quotes,
        triggers: triggers,
        checkedAt: checkedAt,
        summary: summary,
      );
    } catch (error) {
      final summary = '行情刷新失败：$error';
      _settingsRepository.markChecked(checkedAt: checkedAt, message: summary);
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
    _running = true;
  }

  @override
  Future<void> stop() async {
    _running = false;
  }
}
