import '../models/monitor_status.dart';
import '../../services/background/monitoring_policy.dart';

class InMemorySettingsRepository {
  MonitorStatus _status = const MonitorStatus(
    serviceEnabled: false,
    soundEnabled: true,
    pollIntervalSeconds: 20,
    lastCheckAt: null,
    lastMessage: '等待首次刷新A股行情。',
    androidOnboardingShown: false,
  );

  MonitorStatus getStatus() => _status;

  void updateService(bool enabled) {
    _status = _status.copyWith(serviceEnabled: enabled);
  }

  void updateSound(bool enabled) {
    _status = _status.copyWith(soundEnabled: enabled);
  }

  void updatePollIntervalSeconds(int seconds) {
    _status = _status.copyWith(
      pollIntervalSeconds: normalizeMonitorPollIntervalSeconds(seconds),
    );
  }

  void markPrepared(String message) {
    _status = _status.copyWith(
      lastCheckAt: DateTime.now(),
      lastMessage: message,
    );
  }

  void markAndroidOnboardingShown() {
    _status = _status.copyWith(androidOnboardingShown: true);
  }

  void markChecked({required DateTime checkedAt, required String message}) {
    _status = _status.copyWith(lastCheckAt: checkedAt, lastMessage: message);
  }
}
