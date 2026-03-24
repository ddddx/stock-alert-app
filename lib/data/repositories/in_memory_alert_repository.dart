import '../models/alert_rule.dart';

class InMemoryAlertRepository {
  final List<AlertRule> _rules = [
    AlertRule.shortWindowMove(
      id: 'rule-short-window-1',
      stockCode: '600519',
      stockName: '贵州茅台',
      market: 'SH',
      moveThresholdPercent: 1.20,
      lookbackMinutes: 5,
      moveDirection: MoveDirection.either,
      enabled: true,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      note: '监控 5 分钟内的急涨急跌。',
    ),
    AlertRule.stepAlert(
      id: 'rule-step-1',
      stockCode: '000001',
      stockName: '平安银行',
      market: 'SZ',
      stepValue: 0.50,
      stepMetric: StepMetric.percent,
      enabled: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 8)),
      note: '每跨过 0.5% 涨跌幅台阶播报一次。',
    ),
  ];

  List<AlertRule> getAll() => List.unmodifiable(_rules);

  List<AlertRule> getEnabledRules() {
    return _rules.where((rule) => rule.enabled).toList(growable: false);
  }

  void add(AlertRule rule) {
    _rules.insert(0, rule);
  }

  void toggle(String id, bool enabled) {
    final index = _rules.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    _rules[index] = _rules[index].copyWith(enabled: enabled);
  }
}
