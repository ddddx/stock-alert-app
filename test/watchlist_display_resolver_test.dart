import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/monitor_status.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/data/models/watchlist_sort_order.dart';
import 'package:stock_alert_app/data/models/webdav_config.dart';
import 'package:stock_alert_app/features/watchlist/presentation/watchlist_display_resolver.dart';

void main() {
  const resolver = WatchlistDisplayResolver();

  test('keeps original order when sort mode is none', () {
    final items = resolver.buildItems(
      watchlist: _watchlist,
      quotes: _quotes,
      monitorStatus: _status(order: WatchlistSortOrder.none),
      isTradingTime: true,
    );

    expect(
        items.map((item) => item.stock.code), ['600519', '000001', '300750']);
  });

  test('sorts by percent descending and pushes missing data to the end', () {
    final items = resolver.buildItems(
      watchlist: _watchlist,
      quotes: [
        _quote(code: '600519', percent: -1.20),
        _quote(code: '000001', percent: 2.36),
      ],
      monitorStatus: _status(order: WatchlistSortOrder.changePercentDesc),
      isTradingTime: true,
    );

    expect(
        items.map((item) => item.stock.code), ['000001', '600519', '300750']);
    expect(items.last.status, WatchlistItemStatus.waitingRefresh);
  });

  test('refresh failure keeps original order and marks all entries failed', () {
    final items = resolver.buildItems(
      watchlist: _watchlist,
      quotes: _quotes,
      monitorStatus: _status(
        order: WatchlistSortOrder.changePercentAsc,
        lastMessage: '行情刷新失败：network down',
      ),
      isTradingTime: true,
    );

    expect(
        items.map((item) => item.stock.code), ['600519', '000001', '300750']);
    expect(
      items.every((item) => item.status == WatchlistItemStatus.refreshFailed),
      isTrue,
    );
  });

  test('disabled monitoring items are marked disabled and sorted to the end', () {
    final items = resolver.buildItems(
      watchlist: const [
        StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
        StockIdentity(
          code: '000001',
          name: '平安银行',
          market: 'SZ',
          monitoringEnabled: false,
        ),
      ],
      quotes: [
        _quote(code: '600519', percent: -1.20),
        _quote(code: '000001', percent: 2.36),
      ],
      monitorStatus: _status(order: WatchlistSortOrder.changePercentDesc),
      isTradingTime: true,
    );

    expect(items.map((item) => item.stock.code), ['600519', '000001']);
    expect(items.last.status, WatchlistItemStatus.disabled);
  });
}

const _watchlist = [
  StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
  StockIdentity(code: '000001', name: '平安银行', market: 'SZ'),
  StockIdentity(code: '300750', name: '宁德时代', market: 'SZ'),
];

final _quotes = [
  _quote(code: '600519', percent: 1.20),
  _quote(code: '000001', percent: -0.36),
  _quote(code: '300750', percent: 3.18),
];

MonitorStatus _status({
  required WatchlistSortOrder order,
  String lastMessage = 'ready',
}) {
  return MonitorStatus(
    serviceEnabled: true,
    soundEnabled: true,
    pollIntervalSeconds: 20,
    lastCheckAt: null,
    lastMessage: lastMessage,
    androidOnboardingShown: false,
    watchlistSortOrder: order,
    webDavConfig: const WebDavConfig(endpoint: '', username: ''),
  );
}

StockQuoteSnapshot _quote({required String code, required double percent}) {
  return StockQuoteSnapshot(
    code: code,
    name: code,
    market: code.startsWith('6') ? 'SH' : 'SZ',
    lastPrice: 10,
    previousClose: 9.8,
    changeAmount: percent / 100 * 9.8,
    changePercent: percent,
    openPrice: 9.9,
    highPrice: 10.1,
    lowPrice: 9.7,
    volume: 1000,
    timestamp: DateTime(2026, 3, 29, 9, 45),
  );
}
