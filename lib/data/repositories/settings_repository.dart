import '../models/monitor_status.dart';
import '../models/watchlist_sort_order.dart';
import '../models/webdav_config.dart';

abstract class SettingsRepository {
  Future<void> initialize();
  MonitorStatus getStatus();
  Future<void> updateService(bool enabled);
  Future<void> updateSound(bool enabled);
  Future<void> updatePollIntervalSeconds(int seconds);
  Future<void> updateWatchlistSortOrder(WatchlistSortOrder order);
  Future<void> updateWebDavConfig(WebDavConfig config);
  Future<void> markAndroidOnboardingShown();
  Future<void> markPrepared(String message);
  Future<void> markChecked(
      {required DateTime checkedAt, required String message});
}
