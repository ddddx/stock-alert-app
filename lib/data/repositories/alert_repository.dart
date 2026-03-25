import '../models/alert_rule.dart';

abstract class AlertRepository {
  Future<void> initialize();
  List<AlertRule> getAll();
  List<AlertRule> getEnabledRules();
  Future<void> add(AlertRule rule);
  Future<void> toggle(String id, bool enabled);
}
