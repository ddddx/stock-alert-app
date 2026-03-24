import 'stock_identity.dart';

class StockQuoteSnapshot extends StockIdentity {
  const StockQuoteSnapshot({
    required super.code,
    required super.name,
    required super.market,
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

  final double lastPrice;
  final double previousClose;
  final double changeAmount;
  final double changePercent;
  final double openPrice;
  final double highPrice;
  final double lowPrice;
  final double volume;
  final DateTime timestamp;

  bool get isPositive => changeAmount >= 0;
}
