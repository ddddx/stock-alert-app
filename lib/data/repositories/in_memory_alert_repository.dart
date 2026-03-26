import '../models/alert_rule.dart';
import 'alert_repository.dart';

class InMemoryAlertRepository implements AlertRepository {
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
      note: 'Monitor sudden moves within 5 minutes.',
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
      note: 'Announce every additional 0.5% move.',
    ),
  ];

  @override
  List<AlertRule> getAll() => List.unmodifiable(_rules);

  @override
  List<AlertRule> getEnabledRules() {
    return _rules.where((rule) => rule.enabled).toList(growable: false);
  }

  @override
  Future<void> add(AlertRule rule) async {
    _rules.insert(0, rule);
  }

  @override
  Future<void> update(AlertRule rule) async {
    final index = _rules.indexWhere((item) => item.id == rule.id);
    if (index == -1) {
      return;
    }
    _rules[index] = rule;
  }

  @override
  Future<void> delete(String id) async {
    _rules.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> toggle(String id, bool enabled) async {
    final index = _rules.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    _rules[index] = _rules[index].copyWith(enabled: enabled);
  }

  @override
  Future<void> initialize() async {}
}
