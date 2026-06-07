import '../models/market_data_health_snapshot.dart';

abstract class MarketDataHealthRepository {
  Future<void> initialize();
  MarketDataHealthSnapshot? getSnapshot();
  Future<void> replace(MarketDataHealthSnapshot snapshot);
  Future<void> clear();
}

class NoopMarketDataHealthRepository implements MarketDataHealthRepository {
  const NoopMarketDataHealthRepository();

  @override
  Future<void> initialize() async {}

  @override
  MarketDataHealthSnapshot? getSnapshot() => null;

  @override
  Future<void> replace(MarketDataHealthSnapshot snapshot) async {}

  @override
  Future<void> clear() async {}
}
