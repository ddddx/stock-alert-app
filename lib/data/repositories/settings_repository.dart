import '../models/monitor_status.dart';

abstract class SettingsRepository {
  Future<void> initialize();
  MonitorStatus getStatus();
  Future<void> updateService(bool enabled);
  Future<void> updateSound(bool enabled);
  Future<void> updatePollIntervalSeconds(int seconds);
  Future<void> markAndroidOnboardingShown();
  Future<void> markPrepared(String message);
  Future<void> markChecked({required DateTime checkedAt, required String message});
}
