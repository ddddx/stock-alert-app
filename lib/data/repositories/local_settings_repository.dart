import '../models/monitor_status.dart';
import '../models/watchlist_sort_order.dart';
import '../models/webdav_config.dart';
import '../../services/background/monitoring_policy.dart';
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
    lastMessage: '等待首次刷新A股行情。',
    androidOnboardingShown: false,
    watchlistSortOrder: WatchlistSortOrder.none,
    webDavConfig: WebDavConfig(endpoint: '', username: ''),
    marketDataProviderId: 'ashare',
  );

  @override
  Future<void> initialize() async {
    final payload = await _store.readObject();
    if (payload == null || payload.isEmpty) {
      await _persist();
      return;
    }
    _status = MonitorStatus.fromJson(payload);
    final normalized = normalizeMonitorPollIntervalSeconds(
      _status.pollIntervalSeconds,
    );
    if (_status.pollIntervalSeconds != normalized) {
      _status = _status.copyWith(pollIntervalSeconds: normalized);
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
    final normalized = normalizeMonitorPollIntervalSeconds(seconds);
    _status = _status.copyWith(pollIntervalSeconds: normalized);
    await _persist();
  }

  @override
  Future<void> updateMarketDataProviderId(String providerId) async {
    _status = _status.copyWith(marketDataProviderId: providerId);
    await _persist();
  }

  @override
  Future<void> updateWatchlistSortOrder(WatchlistSortOrder order) async {
    _status = _status.copyWith(watchlistSortOrder: order);
    await _persist();
  }

  @override
  Future<void> updateWebDavConfig(WebDavConfig config) async {
    _status = _status.copyWith(webDavConfig: config);
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
  Future<void> markChecked(
      {required DateTime checkedAt, required String message}) async {
    _status = _status.copyWith(lastCheckAt: checkedAt, lastMessage: message);
    await _persist();
  }

  Future<void> _persist() {
    return _store.writeJson(_status.toJson());
  }
}
