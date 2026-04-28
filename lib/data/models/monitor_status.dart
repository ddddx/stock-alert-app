import 'watchlist_sort_order.dart';
import 'webdav_config.dart';

class MonitorStatus {
  const MonitorStatus({
    required this.serviceEnabled,
    required this.soundEnabled,
    required this.pollIntervalSeconds,
    required this.alertCooldownSeconds,
    required this.lastCheckAt,
    required this.lastMessage,
    required this.androidOnboardingShown,
    required this.watchlistSortOrder,
    required this.webDavConfig,
    this.openingBriefingEnabled = false,
    this.closingReviewEnabled = false,
    this.lastOpeningBriefingDayKey = '',
    this.lastClosingReviewDayKey = '',
    this.marketDataProviderId = 'ashare',
  });

  factory MonitorStatus.fromJson(Map<String, dynamic> json) {
    return MonitorStatus(
      serviceEnabled: json['serviceEnabled'] as bool? ?? false,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      pollIntervalSeconds: (json['pollIntervalSeconds'] as int?) ?? 20,
      alertCooldownSeconds: (json['alertCooldownSeconds'] as int?) ?? 120,
      lastCheckAt: json['lastCheckAt'] == null
          ? null
          : DateTime.tryParse(json['lastCheckAt'] as String),
      lastMessage: json['lastMessage'] as String? ?? '等待首次刷新A股行情。',
      androidOnboardingShown: json['androidOnboardingShown'] as bool? ?? false,
      watchlistSortOrder: WatchlistSortOrderX.fromName(
        json['watchlistSortOrder'] as String?,
      ),
      webDavConfig: WebDavConfig.fromJson(
        switch (json['webDavConfig']) {
          Map<String, dynamic>() =>
            json['webDavConfig'] as Map<String, dynamic>,
          Map() => (json['webDavConfig'] as Map).cast<String, dynamic>(),
          _ => null,
        },
      ),
      openingBriefingEnabled: json['openingBriefingEnabled'] as bool? ?? false,
      closingReviewEnabled: json['closingReviewEnabled'] as bool? ?? false,
      lastOpeningBriefingDayKey:
          json['lastOpeningBriefingDayKey'] as String? ?? '',
      lastClosingReviewDayKey:
          json['lastClosingReviewDayKey'] as String? ?? '',
      marketDataProviderId: json['marketDataProviderId'] as String? ?? 'ashare',
    );
  }

  MonitorStatus copyWith({
    bool? serviceEnabled,
    bool? soundEnabled,
    int? pollIntervalSeconds,
    int? alertCooldownSeconds,
    DateTime? lastCheckAt,
    String? lastMessage,
    bool? androidOnboardingShown,
    WatchlistSortOrder? watchlistSortOrder,
    WebDavConfig? webDavConfig,
    bool? openingBriefingEnabled,
    bool? closingReviewEnabled,
    String? lastOpeningBriefingDayKey,
    String? lastClosingReviewDayKey,
    String? marketDataProviderId,
  }) {
    return MonitorStatus(
      serviceEnabled: serviceEnabled ?? this.serviceEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
      alertCooldownSeconds: alertCooldownSeconds ?? this.alertCooldownSeconds,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      lastMessage: lastMessage ?? this.lastMessage,
      androidOnboardingShown:
          androidOnboardingShown ?? this.androidOnboardingShown,
      watchlistSortOrder: watchlistSortOrder ?? this.watchlistSortOrder,
      webDavConfig: webDavConfig ?? this.webDavConfig,
      openingBriefingEnabled:
          openingBriefingEnabled ?? this.openingBriefingEnabled,
      closingReviewEnabled: closingReviewEnabled ?? this.closingReviewEnabled,
      lastOpeningBriefingDayKey:
          lastOpeningBriefingDayKey ?? this.lastOpeningBriefingDayKey,
      lastClosingReviewDayKey:
          lastClosingReviewDayKey ?? this.lastClosingReviewDayKey,
      marketDataProviderId: marketDataProviderId ?? this.marketDataProviderId,
    );
  }

  final bool serviceEnabled;
  final bool soundEnabled;
  final int pollIntervalSeconds;
  final int alertCooldownSeconds;
  final DateTime? lastCheckAt;
  final String lastMessage;
  final bool androidOnboardingShown;
  final WatchlistSortOrder watchlistSortOrder;
  final WebDavConfig webDavConfig;
  final bool openingBriefingEnabled;
  final bool closingReviewEnabled;
  final String lastOpeningBriefingDayKey;
  final String lastClosingReviewDayKey;
  final String marketDataProviderId;

  Map<String, dynamic> toJson() {
    return {
      'serviceEnabled': serviceEnabled,
      'soundEnabled': soundEnabled,
      'pollIntervalSeconds': pollIntervalSeconds,
      'alertCooldownSeconds': alertCooldownSeconds,
      'lastCheckAt': lastCheckAt?.toIso8601String(),
      'lastMessage': lastMessage,
      'androidOnboardingShown': androidOnboardingShown,
      'watchlistSortOrder': watchlistSortOrder.name,
      'webDavConfig': webDavConfig.toJson(),
      'openingBriefingEnabled': openingBriefingEnabled,
      'closingReviewEnabled': closingReviewEnabled,
      'lastOpeningBriefingDayKey': lastOpeningBriefingDayKey,
      'lastClosingReviewDayKey': lastClosingReviewDayKey,
      'marketDataProviderId': marketDataProviderId,
    };
  }
}
