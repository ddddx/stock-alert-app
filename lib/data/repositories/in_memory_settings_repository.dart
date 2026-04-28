import '../models/monitor_status.dart';
import '../models/watchlist_sort_order.dart';
import '../models/webdav_config.dart';
import '../../services/background/monitoring_policy.dart';

class InMemorySettingsRepository {
  MonitorStatus _status = const MonitorStatus(
    serviceEnabled: false,
    soundEnabled: true,
    pollIntervalSeconds: 20,
    alertCooldownSeconds: 120,
    lastCheckAt: null,
    lastMessage: '等待首次刷新A股行情。',
    androidOnboardingShown: false,
    watchlistSortOrder: WatchlistSortOrder.none,
    webDavConfig: WebDavConfig(endpoint: '', username: ''),
    openingBriefingEnabled: false,
    closingReviewEnabled: false,
    lastOpeningBriefingDayKey: '',
    lastClosingReviewDayKey: '',
    marketDataProviderId: 'ashare',
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

  void updateOpeningBriefing(bool enabled) {
    _status = _status.copyWith(openingBriefingEnabled: enabled);
  }

  void updateClosingReview(bool enabled) {
    _status = _status.copyWith(closingReviewEnabled: enabled);
  }

  void updateAlertCooldownSeconds(int seconds) {
    _status = _status.copyWith(
      alertCooldownSeconds: normalizeAlertCooldownSeconds(seconds),
    );
  }

  void updateMarketDataProviderId(String providerId) {
    _status = _status.copyWith(marketDataProviderId: providerId);
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

  void markOpeningBriefingBroadcasted(String tradingDayKey) {
    _status = _status.copyWith(lastOpeningBriefingDayKey: tradingDayKey);
  }

  void markClosingReviewBroadcasted(String tradingDayKey) {
    _status = _status.copyWith(lastClosingReviewDayKey: tradingDayKey);
  }
}
