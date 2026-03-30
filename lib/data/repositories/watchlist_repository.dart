import '../models/stock_identity.dart';

abstract class WatchlistRepository {
  Future<void> initialize();
  List<StockIdentity> getAll();
  Future<bool> add(StockIdentity stock);
  Future<void> remove(String code);
  Future<void> replaceAll(List<StockIdentity> stocks);
  Future<void> updateMonitoringEnabled(String code, bool enabled);
  bool contains(String code);
}
