import 'stock_identity.dart';

class StockQuoteSnapshot extends StockIdentity {
  const StockQuoteSnapshot({
    required super.code,
    required super.name,
    required super.market,
    super.securityTypeName = '',
    this.priceDecimalDigits,
    required this.lastPrice,
    required this.previousClose,
    required this.changeAmount,
    required this.changePercent,
    required this.openPrice,
    required this.highPrice,
    required this.lowPrice,
    required this.volume,
    required this.timestamp,
  });

  final int? priceDecimalDigits;
  final double lastPrice;
  final double previousClose;
  final double changeAmount;
  final double changePercent;
  final double openPrice;
  final double highPrice;
  final double lowPrice;
  final double volume;
  final DateTime timestamp;

  @override
  int get priceScaleDivisor => SecurityPriceScale.divisorFor(
        code: code,
        securityTypeName: securityTypeName,
        priceDecimalDigits: priceDecimalDigits,
      );

  int get resolvedPriceDecimalDigits =>
      priceDecimalDigits ?? (super.priceScaleDivisor >= 1000 ? 3 : 2);

  bool get isPositive => changeAmount >= 0;
}
