import '../models/alert_history_entry.dart';
import '../../services/storage/json_file_store.dart';
import 'history_repository.dart';

class LocalHistoryRepository implements HistoryRepository {
  LocalHistoryRepository({required JsonFileStore store}) : _store = store;

  final JsonFileStore _store;
  final List<AlertHistoryEntry> _entries = [];

  @override
  Future<void> initialize() async {
    final payload = await _store.readList();
    if (payload == null || payload.isEmpty) {
      _entries.clear();
      return;
    }

    var migrated = false;
    _entries
      ..clear()
      ..addAll(
        payload.whereType<Map>().map((item) {
          final entry = AlertHistoryEntry.fromJson(item.cast<String, dynamic>());
          final changed = item.toString() != entry.toJson().toString();
          migrated = migrated || changed;
          return entry;
        }),
      );
    if (migrated) {
      await _persist();
    }
  }

  @override
  List<AlertHistoryEntry> getAll() => List.unmodifiable(_entries);

  @override
  Future<void> add(AlertHistoryEntry entry) async {
    _entries.insert(0, entry);
    if (_entries.length > 100) {
      _entries.removeRange(100, _entries.length);
    }
    await _persist();
  }

  Future<void> _persist() {
    return _store.writeJson(_entries.map((item) => item.toJson()).toList(growable: false));
  }
}
