import 'watchlist_sort_order.dart';
import 'webdav_config.dart';

class MonitorStatus {
  const MonitorStatus({
    required this.serviceEnabled,
    required this.soundEnabled,
    required this.pollIntervalSeconds,
    required this.lastCheckAt,
    required this.lastMessage,
    required this.androidOnboardingShown,
    required this.watchlistSortOrder,
    required this.webDavConfig,
    this.marketDataProviderId = 'ashare',
  });

  factory MonitorStatus.fromJson(Map<String, dynamic> json) {
    return MonitorStatus(
      serviceEnabled: json['serviceEnabled'] as bool? ?? false,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      pollIntervalSeconds: (json['pollIntervalSeconds'] as int?) ?? 20,
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
      marketDataProviderId:
          json['marketDataProviderId'] as String? ?? 'ashare',
    );
  }

  MonitorStatus copyWith({
    bool? serviceEnabled,
    bool? soundEnabled,
    int? pollIntervalSeconds,
    DateTime? lastCheckAt,
    String? lastMessage,
    bool? androidOnboardingShown,
    WatchlistSortOrder? watchlistSortOrder,
    WebDavConfig? webDavConfig,
    String? marketDataProviderId,
  }) {
    return MonitorStatus(
      serviceEnabled: serviceEnabled ?? this.serviceEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      lastMessage: lastMessage ?? this.lastMessage,
      androidOnboardingShown:
          androidOnboardingShown ?? this.androidOnboardingShown,
      watchlistSortOrder: watchlistSortOrder ?? this.watchlistSortOrder,
      webDavConfig: webDavConfig ?? this.webDavConfig,
      marketDataProviderId:
          marketDataProviderId ?? this.marketDataProviderId,
    );
  }

  final bool serviceEnabled;
  final bool soundEnabled;
  final int pollIntervalSeconds;
  final DateTime? lastCheckAt;
  final String lastMessage;
  final bool androidOnboardingShown;
  final WatchlistSortOrder watchlistSortOrder;
  final WebDavConfig webDavConfig;
  final String marketDataProviderId;

  Map<String, dynamic> toJson() {
    return {
      'serviceEnabled': serviceEnabled,
      'soundEnabled': soundEnabled,
      'pollIntervalSeconds': pollIntervalSeconds,
      'lastCheckAt': lastCheckAt?.toIso8601String(),
      'lastMessage': lastMessage,
      'androidOnboardingShown': androidOnboardingShown,
      'watchlistSortOrder': watchlistSortOrder.name,
      'webDavConfig': webDavConfig.toJson(),
      'marketDataProviderId': marketDataProviderId,
    };
  }
}
