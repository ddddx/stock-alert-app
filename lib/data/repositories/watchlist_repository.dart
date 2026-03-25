import '../models/stock_identity.dart';

abstract class WatchlistRepository {
  Future<void> initialize();
  List<StockIdentity> getAll();
  Future<bool> add(StockIdentity stock);
  Future<void> remove(String code);
  bool contains(String code);
}
