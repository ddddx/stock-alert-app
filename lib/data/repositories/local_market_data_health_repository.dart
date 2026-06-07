import '../../services/storage/json_file_store.dart';
import '../models/market_data_health_snapshot.dart';
import 'market_data_health_repository.dart';

class LocalMarketDataHealthRepository implements MarketDataHealthRepository {
  LocalMarketDataHealthRepository({required JsonFileStore store})
      : _store = store;

  final JsonFileStore _store;
  MarketDataHealthSnapshot? _snapshot;

  @override
  Future<void> initialize() async {
    final payload = await _store.readObject();
    if (payload == null || payload.isEmpty) {
      _snapshot = null;
      return;
    }

    _snapshot = MarketDataHealthSnapshot.fromJson(payload);
    final migrated =
        payload['schemaVersion'] != MarketDataHealthSnapshot.schemaVersion;
    if (migrated) {
      await _persist();
    }
  }

  @override
  MarketDataHealthSnapshot? getSnapshot() => _snapshot;

  @override
  Future<void> replace(MarketDataHealthSnapshot snapshot) async {
    _snapshot = snapshot;
    await _persist();
  }

  @override
  Future<void> clear() async {
    _snapshot = null;
    await _store.writeJson({});
  }

  Future<void> _persist() async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      await _store.writeJson({});
      return;
    }
    await _store.writeJson(snapshot.toJson());
  }
}
