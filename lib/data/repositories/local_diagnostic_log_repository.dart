import '../../services/storage/json_file_store.dart';
import '../models/diagnostic_log_entry.dart';
import 'diagnostic_log_repository.dart';

class LocalDiagnosticLogRepository implements DiagnosticLogRepository {
  LocalDiagnosticLogRepository({
    required JsonFileStore store,
    this.maxEntries = 120,
  }) : _store = store;

  final JsonFileStore _store;
  final int maxEntries;
  final List<DiagnosticLogEntry> _entries = [];

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
          final entry =
              DiagnosticLogEntry.fromJson(item.cast<String, dynamic>());
          final changed = item.toString() != entry.toJson().toString();
          migrated = migrated || changed;
          return entry;
        }),
      );
    _trim();
    if (migrated || _entries.length != payload.length) {
      await _persist();
    }
  }

  @override
  List<DiagnosticLogEntry> getAll() => List.unmodifiable(_entries);

  @override
  Future<void> add(DiagnosticLogEntry entry) async {
    if (entry.message.trim().isEmpty) {
      return;
    }
    _entries.insert(0, entry);
    _trim();
    await _persist();
  }

  @override
  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  void _trim() {
    _entries.sort((left, right) => right.timestamp.compareTo(left.timestamp));
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
  }

  Future<void> _persist() {
    return _store.writeJson(
      _entries.map((item) => item.toJson()).toList(growable: false),
    );
  }
}
