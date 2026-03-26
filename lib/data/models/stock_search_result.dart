import 'stock_identity.dart';

class StockSearchResult extends StockIdentity {
  const StockSearchResult({
    required super.code,
    required super.name,
    required super.market,
    super.securityTypeName = '',
    this.pinyin = '',
  });

  final String pinyin;

  StockIdentity toIdentity() {
    return StockIdentity(
      code: code,
      name: name,
      market: market,
      securityTypeName: securityTypeName,
    );
  }
}
