import '../models/monitor_status.dart';
import '../models/watchlist_sort_order.dart';
import '../models/webdav_config.dart';

abstract class SettingsRepository {
  Future<void> initialize();
  MonitorStatus getStatus();
  Future<void> updateService(bool enabled);
  Future<void> updateSound(bool enabled);

  /// Updates whether opening briefing should auto-broadcast at 09:30.
  Future<void> updateOpeningBriefing(bool enabled);

  /// Updates whether closing review should auto-broadcast at 15:05.
  Future<void> updateClosingReview(bool enabled);

  Future<void> updatePollIntervalSeconds(int seconds);
  Future<void> updateAlertCooldownSeconds(int seconds);
  Future<void> updateMarketDataProviderId(String providerId);
  Future<void> updateWatchlistSortOrder(WatchlistSortOrder order);
  Future<void> updateWebDavConfig(WebDavConfig config);
  Future<void> markAndroidOnboardingShown();
  Future<void> markPrepared(String message);
  Future<void> markChecked(
      {required DateTime checkedAt, required String message});

  /// Persists the latest trading day key for successful opening briefing.
  Future<void> markOpeningBriefingBroadcasted(String tradingDayKey);

  /// Persists the latest trading day key for successful closing review.
  Future<void> markClosingReviewBroadcasted(String tradingDayKey);
}
