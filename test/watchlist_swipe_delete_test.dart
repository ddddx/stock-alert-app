import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/monitor_status.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/data/models/stock_search_result.dart';
import 'package:stock_alert_app/data/models/watchlist_sort_order.dart';
import 'package:stock_alert_app/data/models/webdav_config.dart';
import 'package:stock_alert_app/data/repositories/watchlist_repository.dart';
import 'package:stock_alert_app/features/watchlist/presentation/pages/watchlist_page.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('watchlist renders change percent using normalized percent units',
      (
    tester,
  ) async {
    final repository = _FakeWatchlistRepository(
      items: const [
        StockIdentity(code: '600519', name: 'Alpha', market: 'SH'),
      ],
    );

    await tester.pumpWidget(
      buildTestApp(
        WatchlistPage(
          repository: repository,
          marketDataService: _FakeMarketDataService(),
          quotes: [
            StockQuoteSnapshot(
              code: '600519',
              name: 'Alpha',
              market: 'SH',
              lastPrice: 10.20,
              previousClose: 10.0,
              changeAmount: 0.20,
              changePercent: 2.0,
              openPrice: 10.0,
              highPrice: 10.3,
              lowPrice: 9.9,
              volume: 1000,
              timestamp: DateTime(2026, 3, 27, 9, 30),
            ),
          ],
          monitorStatus: _monitoringStatus,
          onRefresh: () async {},
          onSortOrderChanged: (_) async {},
        ),
      ),
    );

    expect(find.text('+¥0.20 / +2.00%'), findsOneWidget);
  });

  testWidgets('watchlist sort button cycles sort order states', (tester) async {
    final changedOrders = <WatchlistSortOrder>[];

    await tester.pumpWidget(
      buildTestApp(
        _SortOrderHarness(
          onOrderChanged: changedOrders.add,
        ),
      ),
    );

    final sortButton = find.byKey(const Key('watchlist-sort-button'));

    expect(sortButton, findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      find.descendant(of: sortButton, matching: find.byIcon(Icons.sort)),
      findsOneWidget,
    );
    expect(find.byTooltip('排序：默认，点击切换为涨跌幅升序'), findsOneWidget);

    await tester.tap(sortButton);
    await tester.pumpAndSettle();

    expect(changedOrders, [WatchlistSortOrder.changePercentAsc]);
    expect(
      find.descendant(of: sortButton, matching: find.byIcon(Icons.trending_up)),
      findsOneWidget,
    );
    expect(find.byTooltip('排序：涨跌幅升序，点击切换为涨跌幅降序'), findsOneWidget);

    await tester.tap(sortButton);
    await tester.pumpAndSettle();

    expect(
      changedOrders,
      [
        WatchlistSortOrder.changePercentAsc,
        WatchlistSortOrder.changePercentDesc,
      ],
    );
    expect(
      find.descendant(
        of: sortButton,
        matching: find.byIcon(Icons.trending_down),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('排序：涨跌幅降序，点击切换为默认'), findsOneWidget);

    await tester.tap(sortButton);
    await tester.pumpAndSettle();

    expect(
      changedOrders,
      [
        WatchlistSortOrder.changePercentAsc,
        WatchlistSortOrder.changePercentDesc,
        WatchlistSortOrder.none,
      ],
    );
    expect(
      find.descendant(of: sortButton, matching: find.byIcon(Icons.sort)),
      findsOneWidget,
    );
    expect(find.byTooltip('排序：默认，点击切换为涨跌幅升序'), findsOneWidget);
  });

  testWidgets(
      'watchlist delete action stays hidden until swipe-left then removes item',
      (
    tester,
  ) async {
    final repository = _FakeWatchlistRepository(
      items: const [
        StockIdentity(code: '600519', name: 'Alpha', market: 'SH'),
      ],
    );

    await tester.pumpWidget(
      buildTestApp(
        WatchlistPage(
          repository: repository,
          marketDataService: _FakeMarketDataService(),
          quotes: const [],
          monitorStatus: _monitoringStatus,
          onRefresh: () async {},
          onSortOrderChanged: (_) async {},
        ),
      ),
    );

    expect(find.text('自选股'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);
    expect(find.byKey(const Key('watchlist-delete-600519')), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    final deleteButton = find.byKey(const Key('watchlist-delete-600519'));
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);

    await tester.drag(
      find.byKey(const ValueKey('watchlist-600519')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNotNull);

    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(repository.getAll(), isEmpty);
    expect(find.textContaining('当前还没有自选股'), findsOneWidget);
  });

  testWidgets('watchlist monitoring toggle updates repository state', (
    tester,
  ) async {
    final repository = _FakeWatchlistRepository(
      items: const [
        StockIdentity(code: '600519', name: 'Alpha', market: 'SH'),
      ],
    );

    await tester.pumpWidget(
      buildTestApp(
        WatchlistPage(
          repository: repository,
          marketDataService: _FakeMarketDataService(),
          quotes: const [],
          monitorStatus: _monitoringStatus,
          onRefresh: () async {},
          onSortOrderChanged: (_) async {},
        ),
      ),
    );

    final toggle = find.byKey(const Key('watchlist-monitor-toggle-600519'));
    expect(toggle, findsOneWidget);
    expect(repository.getAll().single.monitoringEnabled, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(repository.getAll().single.monitoringEnabled, isFalse);
    expect(find.text('未监控'), findsOneWidget);
  });
}

class _FakeWatchlistRepository implements WatchlistRepository {
  _FakeWatchlistRepository({List<StockIdentity>? items}) : _items = [...?items];

  final List<StockIdentity> _items;

  @override
  Future<bool> add(StockIdentity stock) async {
    _items.add(stock);
    return true;
  }

  @override
  bool contains(String code) => _items.any((item) => item.code == code);

  @override
  List<StockIdentity> getAll() => List.unmodifiable(_items);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> remove(String code) async {
    _items.removeWhere((item) => item.code == code);
  }

  @override
  Future<void> replaceAll(List<StockIdentity> stocks) async {
    _items
      ..clear()
      ..addAll(stocks);
  }

  @override
  Future<void> updateMonitoringEnabled(String code, bool enabled) async {
    final index = _items.indexWhere((item) => item.code == code);
    if (index < 0) {
      return;
    }
    _items[index] = _items[index].copyWith(monitoringEnabled: enabled);
  }
}

class _FakeMarketDataService extends AshareMarketDataService {
  @override
  Future<List<StockQuoteSnapshot>> fetchQuotesProgressively(
    List<StockIdentity> stocks, {
    void Function(StockQuoteSnapshot quote)? onQuoteReceived,
    bool preferSingleQuoteRetrieval = false,
  }) async {
    return const [];
  }

  @override
  Future<List<StockSearchResult>> searchStocks(String keyword) async {
    return const [];
  }
}

class _SortOrderHarness extends StatefulWidget {
  const _SortOrderHarness({
    required this.onOrderChanged,
  });

  final ValueChanged<WatchlistSortOrder> onOrderChanged;

  @override
  State<_SortOrderHarness> createState() => _SortOrderHarnessState();
}

class _SortOrderHarnessState extends State<_SortOrderHarness> {
  final _repository = _FakeWatchlistRepository(
    items: const [
      StockIdentity(code: '600519', name: 'Alpha', market: 'SH'),
    ],
  );

  var _monitorStatus = _monitoringStatus;

  @override
  Widget build(BuildContext context) {
    return WatchlistPage(
      repository: _repository,
      marketDataService: _FakeMarketDataService(),
      quotes: const [],
      monitorStatus: _monitorStatus,
      onRefresh: () async {},
      onSortOrderChanged: (order) async {
        widget.onOrderChanged(order);
        setState(() {
          _monitorStatus = _monitorStatus.copyWith(watchlistSortOrder: order);
        });
      },
    );
  }
}

const _monitoringStatus = MonitorStatus(
  serviceEnabled: true,
  soundEnabled: true,
  pollIntervalSeconds: 20,
  lastCheckAt: null,
  lastMessage: 'ready',
  androidOnboardingShown: false,
  watchlistSortOrder: WatchlistSortOrder.none,
  webDavConfig: WebDavConfig(endpoint: '', username: ''),
);
