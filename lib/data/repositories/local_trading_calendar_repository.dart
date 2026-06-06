import '../../services/storage/json_file_store.dart';
import '../models/trading_calendar.dart';

class LocalTradingCalendarRepository {
  LocalTradingCalendarRepository({required JsonFileStore store})
      : _store = store;

  final JsonFileStore _store;
  AshareTradingCalendar _calendar = AshareTradingCalendar.bundled;

  AshareTradingCalendar getCalendar() => _calendar;

  Future<void> initialize() async {
    final payload = await _store.readObject();
    if (payload == null || payload.isEmpty) {
      _calendar = AshareTradingCalendar.bundled.copyWith(
        updatedAt: DateTime.now(),
      );
      await _persist();
      return;
    }

    _calendar = AshareTradingCalendar.fromJson(payload);
    final migrated =
        payload['schemaVersion'] != AshareTradingCalendar.schemaVersion ||
            payload['closedDates'] is! List ||
            payload['openDates'] is! List;
    if (migrated) {
      await _persist();
    }
  }

  Future<void> replace(AshareTradingCalendar calendar) async {
    _calendar = calendar.copyWith(updatedAt: DateTime.now());
    await _persist();
  }

  Future<void> resetToBundled() async {
    await replace(AshareTradingCalendar.bundled);
  }

  Future<void> _persist() {
    return _store.writeJson(_calendar.toJson());
  }
}
