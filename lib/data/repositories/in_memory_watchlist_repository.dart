import '../models/stock_identity.dart';

class InMemoryWatchlistRepository {
  final List<StockIdentity> _items = const [
    StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
    StockIdentity(code: '000001', name: '平安银行', market: 'SZ'),
    StockIdentity(code: '300750', name: '宁德时代', market: 'SZ'),
  ].toList();

  List<StockIdentity> getAll() => List.unmodifiable(_items);

  bool add(StockIdentity stock) {
    if (_items.any((item) => item.code == stock.code)) {
      return false;
    }
    _items.insert(0, stock);
    return true;
  }

  void remove(String code) {
    _items.removeWhere((item) => item.code == code);
  }

  bool contains(String code) {
    return _items.any((item) => item.code == code);
  }
}
