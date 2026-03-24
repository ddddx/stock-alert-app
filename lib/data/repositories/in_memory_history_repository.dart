import '../models/alert_history_entry.dart';

class InMemoryHistoryRepository {
  final List<AlertHistoryEntry> _entries = [];

  List<AlertHistoryEntry> getAll() => List.unmodifiable(_entries);

  void add(AlertHistoryEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > 100) {
      _entries.removeRange(100, _entries.length);
    }
  }
}
