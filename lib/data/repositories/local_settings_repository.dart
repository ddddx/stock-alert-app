import '../models/monitor_status.dart';
import '../../services/storage/json_file_store.dart';
import 'settings_repository.dart';

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository({required JsonFileStore store}) : _store = store;

  final JsonFileStore _store;
  MonitorStatus _status = const MonitorStatus(
    serviceEnabled: false,
    soundEnabled: true,
    lastCheckAt: null,
    lastMessage: '等待首次刷新 A 股行情。',
  );

  @override
  Future<void> initialize() async {
    final payload = await _store.readObject();
    if (payload == null || payload.isEmpty) {
      await _persist();
      return;
    }
    _status = MonitorStatus.fromJson(payload);
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
