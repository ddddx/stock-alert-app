import '../models/monitor_status.dart';
import '../../services/storage/json_file_store.dart';
import 'settings_repository.dart';

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository({required JsonFileStore store}) : _store = store;

  final JsonFileStore _store;
  MonitorStatus _status = const MonitorStatus(
    serviceEnabled: false,
    soundEnabled: true,
    pollIntervalSeconds: 20,
    lastCheckAt: null,
    lastMessage: '等待首次刷新 A 股行情。',
    androidOnboardingShown: false,
  );

  @override
  Future<void> initialize() async {
    final payload = await _store.readObject();
    if (payload == null || payload.isEmpty) {
      await _persist();
      return;
    }
    _status = MonitorStatus.fromJson(payload);
    if (_status.pollIntervalSeconds < 15) {
      _status = _status.copyWith(pollIntervalSeconds: 15);
      await _persist();
    }
  }

  @override
  MonitorStatus getStatus() => _status;

  @override
  Future<void> updateService(bool enabled) async {
    _status = _status.copyWith(serviceEnabled: enabled);
    await _persist();
  }

  @override
  Future<void> updateSound(bool enabled) async {
    _status = _status.copyWith(soundEnabled: enabled);
    await _persist();
  }

  @override
  Future<void> updatePollIntervalSeconds(int seconds) async {
    final normalized = seconds.clamp(15, 300).toInt();
    _status = _status.copyWith(pollIntervalSeconds: normalized);
    await _persist();
  }

  @override
  Future<void> markAndroidOnboardingShown() async {
    if (_status.androidOnboardingShown) {
      return;
    }
    _status = _status.copyWith(androidOnboardingShown: true);
    await _persist();
  }

  @override
  Future<void> markPrepared(String message) async {
    _status = _status.copyWith(
      lastCheckAt: DateTime.now(),
      lastMessage: message,
    );
    await _persist();
  }

  @override
  Future<void> markChecked({required DateTime checkedAt, required String message}) async {
    _status = _status.copyWith(lastCheckAt: checkedAt, lastMessage: message);
    await _persist();
  }

  Future<void> _persist() {
    return _store.writeJson(_status.toJson());
  }
}
