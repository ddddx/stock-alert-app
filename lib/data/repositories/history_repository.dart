import '../models/alert_history_entry.dart';

abstract class HistoryRepository {
  Future<void> initialize();
  List<AlertHistoryEntry> getAll();
  Future<void> add(AlertHistoryEntry entry);
}
