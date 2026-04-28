import 'dart:async';

import '../../core/utils/formatters.dart';
import '../../data/models/alert_history_entry.dart';
import '../../data/models/alert_rule.dart';
import '../../data/models/market_sentiment_snapshot.dart';
import '../../data/models/stock_identity.dart';
import '../../data/models/stock_quote_snapshot.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/watchlist_repository.dart';
import '../audio/audio_alert_service.dart';
import '../market/market_data_provider.dart';
import 'monitoring_policy.dart';

abstract class DailyBriefingService {
  Future<void> start();
  Future<void> stop();
  Future<void> syncNow();
}

class AshareDailyBriefingService implements DailyBriefingService {
  AshareDailyBriefingService({
    required WatchlistRepository watchlistRepository,
    required HistoryRepository historyRepository,
    required SettingsRepository settingsRepository,
    required MarketDataProvider Function() marketDataProviderResolver,
    required AudioAlertService audioAlertService,
    AshareMarketHours marketHours = const AshareMarketHours(),
    DateTime Function()? now,
  })  : _watchlistRepository = watchlistRepository,
        _historyRepository = historyRepository,
        _settingsRepository = settingsRepository,
        _marketDataProviderResolver = marketDataProviderResolver,
        _audioAlertService = audioAlertService,
        _marketHours = marketHours,
        _now = now ?? DateTime.now;

  static const String openingBriefingRuleId = 'system:opening-briefing';
  static const String closingReviewRuleId = 'system:closing-review';

  final WatchlistRepository _watchlistRepository;
  final HistoryRepository _historyRepository;
  final SettingsRepository _settingsRepository;
  final MarketDataProvider Function() _marketDataProviderResolver;
  final AudioAlertService _audioAlertService;
  final AshareMarketHours _marketHours;
  final DateTime Function() _now;

  Timer? _timer;
  bool _running = false;
  bool _syncing = false;

  /// Starts periodic checks for opening and closing daily briefings.
  @override
  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(syncNow()),
    );
    await syncNow();
  }

  /// Stops periodic checks and cancels in-flight scheduling ticks.
  @override
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Immediately evaluates whether opening/closing briefings are due.
  @override
  Future<void> syncNow() async {
    if (_syncing) {
      return;
    }
    _syncing = true;
    try {
      await _syncDueBriefings();
    } finally {
      _syncing = false;
    }
  }

  /// Executes due briefings for the current Shanghai trading day.
  Future<void> _syncDueBriefings() async {
    final status = _settingsRepository.getStatus();
    if (!status.openingBriefingEnabled && !status.closingReviewEnabled) {
      return;
    }

    final now = _now();
    if (!_isTradingDay(now)) {
      return;
    }

    final dayKey = _tradingDayKey(now);
    if (status.openingBriefingEnabled &&
        status.lastOpeningBriefingDayKey != dayKey &&
        _isAfterTime(now, hour: 9, minute: 30)) {
      await _runOpeningBriefing(dayKey, now);
    }

    if (status.closingReviewEnabled &&
        status.lastClosingReviewDayKey != dayKey &&
        _isAfterTime(now, hour: 15, minute: 5)) {
      await _runClosingReview(dayKey, now);
    }
  }

  /// Builds and speaks the 09:30 opening briefing, then appends history.
  Future<void> _runOpeningBriefing(String dayKey, DateTime now) async {
    final watchlist = _enabledWatchlist();
    final provider = _marketDataProviderResolver();
    final quotes = watchlist.isEmpty ? const <StockQuoteSnapshot>[] : await provider.fetchQuotes(watchlist);
    final sentiment = await provider.fetchMarketSentiment();
    final spokenText = _buildOpeningBriefingText(
      quotes: quotes,
      sentiment: sentiment,
    );
    final playedSound = await _speakIfEnabled(spokenText);
    await _historyRepository.add(
      _buildSystemHistoryEntry(
        idPrefix: 'opening-briefing',
        ruleId: openingBriefingRuleId,
        stockName: '开盘简报',
        message: spokenText,
        spokenText: spokenText,
        triggeredAt: now,
        playedSound: playedSound,
      ),
    );
    await _settingsRepository.markOpeningBriefingBroadcasted(dayKey);
  }

  /// Builds and speaks the 15:05 closing review, then appends history.
  Future<void> _runClosingReview(String dayKey, DateTime now) async {
    final watchlist = _enabledWatchlist();
    final provider = _marketDataProviderResolver();
    final quotes = watchlist.isEmpty ? const <StockQuoteSnapshot>[] : await provider.fetchQuotes(watchlist);

    final todayEntries = _historyRepository
        .getAll()
        .where((entry) => _tradingDayKey(entry.triggeredAt) == dayKey)
        .toList(growable: false);
    final alertEntries = todayEntries.where((entry) => !_isSystemEntry(entry));
    final triggerCount = alertEntries.length;
    final playedCount = alertEntries.where((entry) => entry.playedSound).length;

    final spokenText = _buildClosingReviewText(
      quotes: quotes,
      triggerCount: triggerCount,
      playedCount: playedCount,
    );
    final playedSound = await _speakIfEnabled(spokenText);
    await _historyRepository.add(
      _buildSystemHistoryEntry(
        idPrefix: 'closing-review',
        ruleId: closingReviewRuleId,
        stockName: '收盘复盘',
        message: spokenText,
        spokenText: spokenText,
        triggeredAt: now,
        playedSound: playedSound,
      ),
    );
    await _settingsRepository.markClosingReviewBroadcasted(dayKey);
  }

  /// Returns watchlist items that are enabled for monitoring.
  List<StockIdentity> _enabledWatchlist() {
    return _watchlistRepository
        .getAll()
        .where((stock) => stock.monitoringEnabled)
        .toList(growable: false);
  }

  /// Speaks text when the global sound switch is enabled.
  Future<bool> _speakIfEnabled(String text) async {
    final soundEnabled = _settingsRepository.getStatus().soundEnabled;
    if (!soundEnabled) {
      return false;
    }
    return _audioAlertService.speak(text);
  }

  /// Builds the opening briefing script with watchlist and market breadth.
  String _buildOpeningBriefingText({
    required List<StockQuoteSnapshot> quotes,
    required MarketSentimentSnapshot sentiment,
  }) {
    if (quotes.isEmpty) {
      return '开盘简报：当前没有开启监控的自选股。全市场上涨${sentiment.advancingCount}家，下跌${sentiment.decliningCount}家，涨跌比${_ratioText(sentiment.advancingCount, sentiment.decliningCount)}，涨停${sentiment.limitUpCount}家。';
    }

    var gapUp = 0;
    var gapFlat = 0;
    var gapDown = 0;
    final details = <String>[];

    for (final quote in quotes) {
      final gapPercent = _openingGapPercent(quote);
      if (gapPercent > 0.05) {
        gapUp += 1;
        details.add('${quote.readableName}高开${Formatters.percent(gapPercent)}');
      } else if (gapPercent < -0.05) {
        gapDown += 1;
        details.add('${quote.readableName}低开${Formatters.percent(gapPercent)}');
      } else {
        gapFlat += 1;
        details.add('${quote.readableName}平开${Formatters.percent(gapPercent)}');
      }
    }

    final spotlight = details.take(3).join('，');
    return '开盘简报：自选${quotes.length}只，高开$gapUp只，平开$gapFlat只，低开$gapDown只。$spotlight。全市场上涨${sentiment.advancingCount}家，下跌${sentiment.decliningCount}家，涨跌比${_ratioText(sentiment.advancingCount, sentiment.decliningCount)}，涨停${sentiment.limitUpCount}家。';
  }

  /// Builds the closing review script with quote stats and reminder stats.
  String _buildClosingReviewText({
    required List<StockQuoteSnapshot> quotes,
    required int triggerCount,
    required int playedCount,
  }) {
    if (quotes.isEmpty) {
      return '收盘复盘：当前没有开启监控的自选股。今日触发提醒$triggerCount次，语音播报成功$playedCount次。';
    }

    var riseCount = 0;
    var flatCount = 0;
    var fallCount = 0;
    StockQuoteSnapshot best = quotes.first;
    StockQuoteSnapshot worst = quotes.first;
    for (final quote in quotes) {
      if (quote.changePercent > 0.01) {
        riseCount += 1;
      } else if (quote.changePercent < -0.01) {
        fallCount += 1;
      } else {
        flatCount += 1;
      }
      if (quote.changePercent > best.changePercent) {
        best = quote;
      }
      if (quote.changePercent < worst.changePercent) {
        worst = quote;
      }
    }

    return '收盘复盘：自选${quotes.length}只，上涨$riseCount只，下跌$fallCount只，平盘$flatCount只。最大涨幅${best.readableName}${Formatters.percent(best.changePercent)}，最大跌幅${worst.readableName}${Formatters.percent(worst.changePercent)}。今日触发提醒$triggerCount次，语音播报成功$playedCount次。';
  }

  /// Computes opening gap percent using open price relative to previous close.
  double _openingGapPercent(StockQuoteSnapshot quote) {
    if (quote.previousClose <= 0) {
      return 0;
    }
    return (quote.openPrice - quote.previousClose) / quote.previousClose * 100;
  }

  /// Formats advancing/declining ratio into readable text.
  String _ratioText(int up, int down) {
    if (down <= 0) {
      return up <= 0 ? '0.00' : '∞';
    }
    return (up / down).toStringAsFixed(2);
  }

  /// Determines whether current local time has reached a target time.
  bool _isAfterTime(
    DateTime now, {
    required int hour,
    required int minute,
  }) {
    final localNow = now.toLocal();
    final threshold = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      hour,
      minute,
    );
    return !localNow.isBefore(threshold);
  }

  /// Checks whether a local date belongs to a valid A-share trading day.
  bool _isTradingDay(DateTime moment) {
    final local = moment.toLocal();
    final probe = DateTime(local.year, local.month, local.day, 10, 0);
    return _marketHours.isTradingTime(probe);
  }

  /// Produces Shanghai trading-day key in yyyy-MM-dd format.
  String _tradingDayKey(DateTime moment) {
    final shanghaiMoment = moment.toUtc().add(const Duration(hours: 8));
    final year = shanghaiMoment.year.toString().padLeft(4, '0');
    final month = shanghaiMoment.month.toString().padLeft(2, '0');
    final day = shanghaiMoment.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Builds a synthetic history entry for system-level daily broadcasts.
  AlertHistoryEntry _buildSystemHistoryEntry({
    required String idPrefix,
    required String ruleId,
    required String stockName,
    required String message,
    required String spokenText,
    required DateTime triggeredAt,
    required bool playedSound,
  }) {
    return AlertHistoryEntry(
      id: '$idPrefix-${triggeredAt.millisecondsSinceEpoch}',
      ruleId: ruleId,
      ruleType: AlertRuleType.shortWindowMove,
      stockCode: 'SYSTEM_BRIEFING',
      stockName: stockName,
      market: 'SH',
      securityTypeName: 'SYSTEM',
      priceDecimalDigits: 2,
      triggeredAt: triggeredAt,
      currentPrice: 0,
      referencePrice: 0,
      changeAmount: 0,
      changePercent: 0,
      message: message,
      spokenText: spokenText,
      playedSound: playedSound,
    );
  }

  /// Returns whether a history entry was generated by system briefing tasks.
  bool _isSystemEntry(AlertHistoryEntry entry) {
    return entry.ruleId == openingBriefingRuleId ||
        entry.ruleId == closingReviewRuleId;
  }
}
