import '../models/stock_identity.dart';
import '../../services/storage/json_file_store.dart';
import 'watchlist_repository.dart';

class LocalWatchlistRepository implements WatchlistRepository {
  LocalWatchlistRepository({required JsonFileStore store}) : _store = store;

  final JsonFileStore _store;
  final List<StockIdentity> _items = [];

  @override
  Future<void> initialize() async {
    final payload = await _store.readList();
    if (payload == null || payload.isEmpty) {
      _items
        ..clear()
        ..addAll(const [
          StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
          StockIdentity(code: '000001', name: '平安银行', market: 'SZ'),
          StockIdentity(code: '300750', name: '宁德时代', market: 'SZ'),
        ]);
      await _persist();
      return;
    }

    _items
      ..clear()
      ..addAll(
        payload.whereType<Map>().map(
              (item) => StockIdentity.fromJson(item.cast<String, dynamic>()),
            ),
      );
  }

  @override
  List<StockIdentity> getAll() => List.unmodifiable(_items);

  @override
  Future<bool> add(StockIdentity stock) async {
    if (_items.any((item) => item.code == stock.code)) {
      return false;
    }
    _items.insert(0, stock);
    await _persist();
    return true;
  }

  @override
  Future<void> remove(String code) async {
    _items.removeWhere((item) => item.code == code);
    await _persist();
  }

  @override
  Future<void> replaceAll(List<StockIdentity> stocks) async {
    _items
      ..clear()
      ..addAll(stocks);
    await _persist();
  }

  @override
  Future<void> updateMonitoringEnabled(String code, bool enabled) async {
    final index = _items.indexWhere((item) => item.code == code);
    if (index < 0) {
      return;
    }
    _items[index] = _items[index].copyWith(monitoringEnabled: enabled);
    await _persist();
  }

  @override
  bool contains(String code) {
    return _items.any((item) => item.code == code);
  }

  Future<void> _persist() {
    return _store
        .writeJson(_items.map((item) => item.toJson()).toList(growable: false));
  }
}
