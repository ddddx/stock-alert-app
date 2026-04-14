import '../../data/models/alert_history_entry.dart';
import '../../data/models/alert_rule.dart';
import '../../data/models/rule_evaluation_state.dart';
import '../../data/models/stock_quote_snapshot.dart';
import 'alert_message_builder.dart';

class AlertTrigger {
  const AlertTrigger({
    required this.rule,
    required this.quote,
    required this.triggeredAt,
    required this.referencePrice,
    required this.changeAmount,
    required this.changePercent,
    required this.message,
    required this.spokenText,
  });

  final AlertRule rule;
  final StockQuoteSnapshot quote;
  final DateTime triggeredAt;
  final double referencePrice;
  final double changeAmount;
  final double changePercent;
  final String message;
  final String spokenText;

  AlertHistoryEntry toHistoryEntry({required bool playedSound}) {
    return AlertHistoryEntry(
      id: '${rule.id}-${quote.code}-${triggeredAt.millisecondsSinceEpoch}',
      ruleId: rule.id,
      ruleType: rule.type,
      stockCode: quote.code,
      stockName: quote.name,
      market: quote.market,
      securityTypeName: quote.securityTypeName,
      priceDecimalDigits: quote.resolvedPriceDecimalDigits,
      triggeredAt: triggeredAt,
      currentPrice: quote.lastPrice,
      referencePrice: referencePrice,
      changeAmount: changeAmount,
      changePercent: changePercent,
      message: message,
      spokenText: spokenText,
      playedSound: playedSound,
    );
  }
}

class AlertRuleEngine {
  AlertRuleEngine({required AlertMessageBuilder messageBuilder})
      : _messageBuilder = messageBuilder;

  final AlertMessageBuilder _messageBuilder;
  final Map<String, List<StockQuoteSnapshot>> _historyByCode = {};
  final Map<String, RuleEvaluationState> _states = {};

  List<AlertTrigger> processQuotes({
    required List<AlertRule> rules,
    required List<StockQuoteSnapshot> quotes,
  }) {
    for (final quote in quotes) {
      _appendHistory(quote);
    }

    final now = DateTime.now();
    final enabledRules =
        rules.where((item) => item.enabled).toList(growable: false);
    final liveStateKeys = <String>{};
    final triggers = <AlertTrigger>[];

    for (final rule in enabledRules) {
      for (final quote
          in quotes.where((item) => rule.appliesToCode(item.code))) {
        final stateKey = rule.stateKeyFor(quote.code);
        liveStateKeys.add(stateKey);
        final state =
            _states[stateKey] ?? RuleEvaluationState(ruleId: stateKey);
        switch (rule.type) {
          case AlertRuleType.shortWindowMove:
            final outcome = _evaluateShortWindowRule(rule, quote, state, now);
            _states[stateKey] = outcome.state;
            if (outcome.trigger != null) {
              triggers.add(outcome.trigger!);
            }
          case AlertRuleType.stepAlert:
            final outcome = _evaluateStepRule(rule, quote, state, now);
            _states[stateKey] = outcome.state;
            if (outcome.trigger != null) {
              triggers.add(outcome.trigger!);
            }
        }
      }
    }

    _states.removeWhere((key, _) => !liveStateKeys.contains(key));

    return triggers;
  }

  void removeRule(String ruleId) {
    _states
        .removeWhere((key, _) => key == ruleId || key.startsWith('$ruleId:'));
  }

  void replaceRule(AlertRule previousRule, AlertRule nextRule) {
    if (previousRule.id != nextRule.id) {
      removeRule(previousRule.id);
      return;
    }

    final previousTargets = _sortedTargetCodes(previousRule);
    final nextTargets = _sortedTargetCodes(nextRule);

    if (previousRule.type != nextRule.type ||
        previousRule.moveThresholdPercent != nextRule.moveThresholdPercent ||
        previousRule.lookbackMinutes != nextRule.lookbackMinutes ||
        previousRule.moveDirection != nextRule.moveDirection ||
        previousRule.stepValue != nextRule.stepValue ||
        previousRule.stepMetric != nextRule.stepMetric ||
        previousRule.anchorPricesByCode.toString() !=
            nextRule.anchorPricesByCode.toString() ||
        previousTargets.join(',') != nextTargets.join(',')) {
      removeRule(previousRule.id);
    }
  }

  List<String> _sortedTargetCodes(AlertRule rule) {
    final targetCodes = rule.applyToAllWatchlist
        ? <String>['*']
        : rule.targetStocks.map((item) => item.code).toList(growable: true);
    targetCodes.sort();
    return targetCodes;
  }

  void reset() {
    _historyByCode.clear();
    _states.clear();
  }

  void _appendHistory(StockQuoteSnapshot quote) {
    final history = _historyByCode.putIfAbsent(quote.code, () => []);
    history.add(quote);
    final cutoff = quote.timestamp.subtract(const Duration(hours: 2));
    history.removeWhere((item) => item.timestamp.isBefore(cutoff));
  }

  _EvaluationOutcome _evaluateShortWindowRule(
    AlertRule rule,
    StockQuoteSnapshot current,
    RuleEvaluationState state,
    DateTime now,
  ) {
    final history = _historyByCode[current.code] ?? const [];
    final lookbackMinutes = rule.lookbackMinutes ?? 0;
    if (lookbackMinutes <= 0 || history.length < 2) {
      return _EvaluationOutcome(state: state.copyWith(active: false));
    }

    final cutoff =
        current.timestamp.subtract(Duration(minutes: lookbackMinutes));
    final window =
        history.where((item) => !item.timestamp.isBefore(cutoff)).toList();
    if (window.length < 2) {
      return _EvaluationOutcome(state: state.copyWith(active: false));
    }

    final reference = window.first;
    if (reference.lastPrice <= 0) {
      return _EvaluationOutcome(state: state.copyWith(active: false));
    }

    final changeAmount = current.lastPrice - reference.lastPrice;
    final changePercent = changeAmount / reference.lastPrice * 100;
    final threshold = rule.moveThresholdPercent ?? 0;
    final matches = switch (rule.moveDirection ?? MoveDirection.either) {
      MoveDirection.up => changePercent >= threshold,
      MoveDirection.down => changePercent <= -threshold,
      MoveDirection.either => changePercent.abs() >= threshold,
    };

    if (!matches) {
      return _EvaluationOutcome(state: state.copyWith(active: false));
    }

    if (state.active) {
      return _EvaluationOutcome(state: state.copyWith(active: true));
    }

    final message = _messageBuilder.buildShortWindowMessage(
      rule: rule,
      current: current,
      changeAmount: changeAmount,
      changePercent: changePercent,
    );

    return _EvaluationOutcome(
      state: state.copyWith(active: true, lastTriggeredAt: now),
      trigger: AlertTrigger(
        rule: rule,
        quote: current,
        triggeredAt: now,
        referencePrice: reference.lastPrice,
        changeAmount: changeAmount,
        changePercent: changePercent,
        message: message,
        spokenText: message,
      ),
    );
  }

  _EvaluationOutcome _evaluateStepRule(
    AlertRule rule,
    StockQuoteSnapshot current,
    RuleEvaluationState state,
    DateTime now,
  ) {
    final stepValue = rule.stepValue ?? 0;
    if (stepValue <= 0) {
      return _EvaluationOutcome(state: state);
    }

    final currentIndex = _stepIndex(rule, current);
    if (state.lastStepIndex == null) {
      return _EvaluationOutcome(
        state: state.copyWith(lastStepIndex: currentIndex, active: false),
      );
    }

    if (currentIndex == state.lastStepIndex) {
      return _EvaluationOutcome(state: state.copyWith(active: false));
    }

    if (rule.stepMetric == StepMetric.percent && currentIndex == 0) {
      return _EvaluationOutcome(
        state: state.copyWith(lastStepIndex: currentIndex, active: false),
      );
    }

    final referenceValue = rule.stepMetric == StepMetric.percent
        ? current.previousClose
        : (rule.anchorPriceFor(current.code) ?? current.lastPrice);
    final previousIndex = state.lastStepIndex!;
    final crossedAmount = current.lastPrice - referenceValue;
    final crossedPercent =
        referenceValue == 0 ? 0.0 : crossedAmount / referenceValue * 100.0;
    final message = _messageBuilder.buildStepAlertMessage(
      rule: rule,
      current: current,
      previousIndex: previousIndex,
      currentIndex: currentIndex,
      referenceValue: referenceValue,
      crossedAmount: crossedAmount,
      crossedPercent: crossedPercent,
    );

    return _EvaluationOutcome(
      state: state.copyWith(
        active: true,
        lastStepIndex: currentIndex,
        lastTriggeredAt: now,
      ),
      trigger: AlertTrigger(
        rule: rule,
        quote: current,
        triggeredAt: now,
        referencePrice: referenceValue,
        changeAmount: crossedAmount,
        changePercent: crossedPercent,
        message: message,
        spokenText: message,
      ),
    );
  }

  int _stepIndex(AlertRule rule, StockQuoteSnapshot quote) {
    final stepValue = rule.stepValue ?? 0;
    if (stepValue <= 0) {
      return 0;
    }
    if (rule.stepMetric == StepMetric.percent) {
      return _bandIndex(quote.changePercent / stepValue);
    }
    final anchor = rule.anchorPriceFor(quote.code) ?? quote.lastPrice;
    return _bandIndex((quote.lastPrice - anchor) / stepValue);
  }

  int _bandIndex(double value) {
    if (value >= 0) {
      return value.floor();
    }
    return value.ceil();
  }
}

class _EvaluationOutcome {
  const _EvaluationOutcome({required this.state, this.trigger});

  final RuleEvaluationState state;
  final AlertTrigger? trigger;
}
