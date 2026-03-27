import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_quote_snapshot.dart';
import 'package:stock_alert_app/data/models/stock_search_result.dart';
import 'package:stock_alert_app/data/repositories/watchlist_repository.dart';
import 'package:stock_alert_app/features/watchlist/presentation/pages/watchlist_page.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';

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
      MaterialApp(
        home: Scaffold(
          body: WatchlistPage(
            repository: repository,
            marketDataService: _FakeMarketDataService(),
            quotes: const [
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
            onRefresh: () async {},
          ),
        ),
      ),
    );

    expect(find.text('+¥0.20 / +2.00%'), findsOneWidget);
  });

  testWidgets(
      'watchlist delete stays hidden until swipe-left then deletes on tap', (
    tester,
  ) async {
    final repository = _FakeWatchlistRepository(
      items: const [
        StockIdentity(code: '600519', name: 'Alpha', market: 'SH'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WatchlistPage(
            repository: repository,
            marketDataService: _FakeMarketDataService(),
            quotes: const [],
            onRefresh: () async {},
          ),
        ),
      ),
    );

    expect(find.text('自选股'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);

    final deleteFinder = find.byKey(const Key('watchlist-delete-600519'));
    expect(deleteFinder, findsOneWidget);
    expect(tester.widget<FilledButton>(deleteFinder).onPressed, isNull);

    await tester.drag(
      find.byKey(const ValueKey('watchlist-600519')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(deleteFinder).onPressed, isNotNull);
    expect(
      tester.hitTestOnBinding(tester.getCenter(deleteFinder)).path.any(
            (entry) => entry.target == tester.renderObject(deleteFinder),
          ),
      isTrue,
    );

    await tester.tap(deleteFinder);
    await tester.pumpAndSettle();

    expect(repository.getAll(), isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
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
}

class _FakeMarketDataService extends AshareMarketDataService {
  @override
  Future<List<StockSearchResult>> searchStocks(String keyword) async {
    return const [];
  }
}
