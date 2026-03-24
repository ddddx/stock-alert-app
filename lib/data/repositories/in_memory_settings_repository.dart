import '../models/monitor_status.dart';

class InMemorySettingsRepository {
  MonitorStatus _status = const MonitorStatus(
    serviceEnabled: false,
    soundEnabled: true,
    lastCheckAt: null,
    lastMessage: '等待首次刷新 A 股行情。',
  );

  MonitorStatus getStatus() => _status;

  void updateService(bool enabled) {
    _status = _status.copyWith(serviceEnabled: enabled);
  }

  void updateSound(bool enabled) {
    _status = _status.copyWith(soundEnabled: enabled);
  }

  void markPrepared(String message) {
    _status = _status.copyWith(
      lastCheckAt: DateTime.now(),
      lastMessage: message,
    );
  }

  void markChecked({required DateTime checkedAt, required String message}) {
    _status = _status.copyWith(lastCheckAt: checkedAt, lastMessage: message);
  }
}
