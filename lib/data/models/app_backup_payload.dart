import 'alert_rule.dart';
import 'stock_identity.dart';
import 'watchlist_sort_order.dart';

class AppBackupPreferences {
  const AppBackupPreferences({
    required this.soundEnabled,
    required this.pollIntervalSeconds,
    required this.watchlistSortOrder,
    this.marketDataProviderId = 'ashare',
  });

  factory AppBackupPreferences.fromJson(Map<String, dynamic> json) {
    return AppBackupPreferences(
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      pollIntervalSeconds: json['pollIntervalSeconds'] as int? ?? 20,
      watchlistSortOrder: WatchlistSortOrderX.fromName(
        json['watchlistSortOrder'] as String?,
      ),
      marketDataProviderId:
          json['marketDataProviderId'] as String? ?? 'ashare',
    );
  }

  final bool soundEnabled;
  final int pollIntervalSeconds;
  final WatchlistSortOrder watchlistSortOrder;
  final String marketDataProviderId;

  Map<String, dynamic> toJson() {
    return {
      'soundEnabled': soundEnabled,
      'pollIntervalSeconds': pollIntervalSeconds,
      'watchlistSortOrder': watchlistSortOrder.name,
      'marketDataProviderId': marketDataProviderId,
    };
  }
}

class AppBackupPayload {
  const AppBackupPayload({
    required this.schemaVersion,
    required this.exportedAt,
    required this.watchlist,
    required this.alertRules,
    required this.preferences,
  });

  factory AppBackupPayload.fromJson(Map<String, dynamic> json) {
    final watchlist = (json['watchlist'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => StockIdentity.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
    final alertRules = (json['alertRules'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => AlertRule.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
    final preferences = switch (json['preferences']) {
      Map<String, dynamic>() => json['preferences'] as Map<String, dynamic>,
      Map() => (json['preferences'] as Map).cast<String, dynamic>(),
      _ => <String, dynamic>{},
    };

    return AppBackupPayload(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      watchlist: watchlist,
      alertRules: alertRules,
      preferences: AppBackupPreferences.fromJson(preferences),
    );
  }

  final int schemaVersion;
  final DateTime exportedAt;
  final List<StockIdentity> watchlist;
  final List<AlertRule> alertRules;
  final AppBackupPreferences preferences;

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'exportedAt': exportedAt.toIso8601String(),
      'watchlist':
          watchlist.map((item) => item.toJson()).toList(growable: false),
      'alertRules':
          alertRules.map((item) => item.toJson()).toList(growable: false),
      'preferences': preferences.toJson(),
    };
  }
}
