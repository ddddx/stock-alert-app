import '../models/stock_identity.dart';

abstract class WatchlistRepository {
  Future<void> initialize();
  List<StockIdentity> getAll();
  Future<bool> add(StockIdentity stock);
  Future<void> remove(String code);
  Future<void> replaceAll(List<StockIdentity> stocks);
  bool contains(String code);
}
