import '../models/diagnostic_log_entry.dart';

abstract class DiagnosticLogRepository {
  Future<void> initialize();
  List<DiagnosticLogEntry> getAll();
  Future<void> add(DiagnosticLogEntry entry);
  Future<void> clear();
}

class NoopDiagnosticLogRepository implements DiagnosticLogRepository {
  const NoopDiagnosticLogRepository();

  @override
  Future<void> initialize() async {}

  @override
  List<DiagnosticLogEntry> getAll() => const [];

  @override
  Future<void> add(DiagnosticLogEntry entry) async {}

  @override
  Future<void> clear() async {}
}
