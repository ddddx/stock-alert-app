import 'stock_identity.dart';

class StockSearchResult extends StockIdentity {
  const StockSearchResult({
    required super.code,
    required super.name,
    required super.market,
    this.securityTypeName = '',
    this.pinyin = '',
  });

  final String securityTypeName;
  final String pinyin;

  StockIdentity toIdentity() {
    return StockIdentity(code: code, name: name, market: market);
  }

  String get subtitle {
    if (securityTypeName.isEmpty) {
      return '$market A股';
    }
    return '$market A股 · $securityTypeName';
  }
}
