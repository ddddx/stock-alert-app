import '../models/alert_rule.dart';
import '../../services/storage/json_file_store.dart';
import 'alert_repository.dart';

class LocalAlertRepository implements AlertRepository {
  LocalAlertRepository({required JsonFileStore store}) : _store = store;

  final JsonFileStore _store;
  final List<AlertRule> _rules = [];

  @override
  Future<void> initialize() async {
    final payload = await _store.readList();
    if (payload == null || payload.isEmpty) {
      _rules
        ..clear()
        ..addAll([
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
        ]);
      await _persist();
      return;
    }

    _rules
      ..clear()
      ..addAll(
        payload.whereType<Map>().map(
              (item) => AlertRule.fromJson(item.cast<String, dynamic>()),
            ),
      );
  }

  @override
  List<AlertRule> getAll() => List.unmodifiable(_rules);

  @override
  List<AlertRule> getEnabledRules() {
    return _rules.where((rule) => rule.enabled).toList(growable: false);
  }

  @override
  Future<void> add(AlertRule rule) async {
    _rules.insert(0, rule);
    await _persist();
  }

  @override
  Future<void> toggle(String id, bool enabled) async {
    final index = _rules.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    _rules[index] = _rules[index].copyWith(enabled: enabled);
    await _persist();
  }

  Future<void> _persist() {
    return _store.writeJson(_rules.map((item) => item.toJson()).toList(growable: false));
  }
}
