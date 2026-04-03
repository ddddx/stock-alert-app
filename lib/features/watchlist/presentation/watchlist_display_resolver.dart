import '../../../data/models/monitor_status.dart';
import '../../../data/models/stock_identity.dart';
import '../../../data/models/stock_quote_snapshot.dart';
import '../../../data/models/watchlist_sort_order.dart';

enum WatchlistItemStatus {
  monitoring,
  disabled,
  paused,
  offHours,
  refreshFailed,
  dataAbnormal,
  waitingRefresh,
}

extension WatchlistItemStatusX on WatchlistItemStatus {
  String get label {
    switch (this) {
      case WatchlistItemStatus.monitoring:
        return '监控中';
      case WatchlistItemStatus.disabled:
        return '未监控';
      case WatchlistItemStatus.paused:
        return '已暂停';
      case WatchlistItemStatus.offHours:
        return '非交易时段';
      case WatchlistItemStatus.refreshFailed:
        return '刷新失败';
      case WatchlistItemStatus.dataAbnormal:
        return '数据异常';
      case WatchlistItemStatus.waitingRefresh:
        return '待刷新';
    }
  }

  String get detail {
    switch (this) {
      case WatchlistItemStatus.monitoring:
        return '当前处于可监控状态。';
      case WatchlistItemStatus.disabled:
        return '已关闭单股监控，不参与后台轮询和提醒。';
      case WatchlistItemStatus.paused:
        return '后台监控已暂停，可在设置页重新开启。';
      case WatchlistItemStatus.offHours:
        return '当前不在 A 股交易时段。';
      case WatchlistItemStatus.refreshFailed:
        return '最近一次刷新未成功，请稍后重试。';
      case WatchlistItemStatus.dataAbnormal:
        return '行情字段不完整，暂不参与排序。';
      case WatchlistItemStatus.waitingRefresh:
        return '暂未拿到最新行情，请手动刷新。';
    }
  }
}

class WatchlistDisplayItem {
  const WatchlistDisplayItem({
    required this.stock,
    required this.quote,
    required this.status,
    required this.originalIndex,
  });

  final StockIdentity stock;
  final StockQuoteSnapshot? quote;
  final WatchlistItemStatus status;
  final int originalIndex;

  bool get hasSortablePercent {
    final percent = quote?.changePercent;
    if (percent == null) {
      return false;
    }
    return percent.isFinite;
  }
}

class WatchlistDisplayResolver {
  const WatchlistDisplayResolver();

  List<WatchlistDisplayItem> buildItems({
    required List<StockIdentity> watchlist,
    required List<StockQuoteSnapshot> quotes,
    required MonitorStatus monitorStatus,
    required bool isTradingTime,
    Set<String> pendingRefreshCodes = const <String>{},
    bool isRefreshing = false,
  }) {
    final quoteByCode = {for (final quote in quotes) quote.code: quote};
    final normalizedMessage = monitorStatus.lastMessage.toLowerCase();
    const refreshFailureMarker = '\u884c\u60c5\u5237\u65b0\u5931\u8d25';
    final hasRefreshError = !isRefreshing &&
        (normalizedMessage.contains('refresh failed') ||
            monitorStatus.lastMessage.contains(refreshFailureMarker));
    final items = <WatchlistDisplayItem>[];

    for (var index = 0; index < watchlist.length; index += 1) {
      final stock = watchlist[index];
      final quote = quoteByCode[stock.code];
      items.add(
        WatchlistDisplayItem(
          stock: stock,
          quote: quote,
          status: _resolveStatus(
            stock: stock,
            quote: quote,
            monitorStatus: monitorStatus,
            isTradingTime: isTradingTime,
            hasRefreshError: hasRefreshError,
            isPendingRefresh: pendingRefreshCodes.contains(stock.code),
            isRefreshing: isRefreshing,
          ),
          originalIndex: index,
        ),
      );
    }

    if (monitorStatus.watchlistSortOrder == WatchlistSortOrder.none ||
        hasRefreshError) {
      return items;
    }

    final sortable = <WatchlistDisplayItem>[];
    final trailing = <WatchlistDisplayItem>[];
    for (final item in items) {
      if (item.status == WatchlistItemStatus.refreshFailed ||
          item.status == WatchlistItemStatus.disabled ||
          item.quote == null ||
          !item.hasSortablePercent) {
        trailing.add(item);
        continue;
      }
      sortable.add(item);
    }

    sortable.sort((left, right) {
      final result =
          left.quote!.changePercent.compareTo(right.quote!.changePercent);
      if (result == 0) {
        return left.originalIndex.compareTo(right.originalIndex);
      }
      if (monitorStatus.watchlistSortOrder ==
          WatchlistSortOrder.changePercentAsc) {
        return result;
      }
      return -result;
    });

    return [...sortable, ...trailing];
  }

  WatchlistItemStatus _resolveStatus({
    required StockIdentity stock,
    required StockQuoteSnapshot? quote,
    required MonitorStatus monitorStatus,
    required bool isTradingTime,
    required bool hasRefreshError,
    required bool isPendingRefresh,
    required bool isRefreshing,
  }) {
    if (!stock.monitoringEnabled) {
      return WatchlistItemStatus.disabled;
    }
    if (hasRefreshError) {
      return WatchlistItemStatus.refreshFailed;
    }
    if (isPendingRefresh) {
      return WatchlistItemStatus.waitingRefresh;
    }
    if (quote == null) {
      if (!monitorStatus.serviceEnabled) {
        return WatchlistItemStatus.paused;
      }
      if (!isTradingTime) {
        return WatchlistItemStatus.offHours;
      }
      return WatchlistItemStatus.waitingRefresh;
    }
    if (!quote.changePercent.isFinite) {
      return WatchlistItemStatus.dataAbnormal;
    }
    if (!monitorStatus.serviceEnabled && !isRefreshing) {
      return WatchlistItemStatus.paused;
    }
    if (!isTradingTime && !isRefreshing) {
      return WatchlistItemStatus.offHours;
    }
    return WatchlistItemStatus.monitoring;
  }
}
