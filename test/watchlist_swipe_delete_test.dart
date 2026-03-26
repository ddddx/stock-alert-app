import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_search_result.dart';
import 'package:stock_alert_app/data/repositories/watchlist_repository.dart';
import 'package:stock_alert_app/features/watchlist/presentation/pages/watchlist_page.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';

void main() {
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

    final deleteFinder = find.byKey(const Key('watchlist-delete-600519'));
    expect(deleteFinder, findsOneWidget);
    expect(tester.widget<FilledButton>(deleteFinder).onPressed, isNull);

    await tester.drag(
      find.byKey(const ValueKey('watchlist-600519')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(deleteFinder).onPressed, isNotNull);

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
