class AshareTradingCalendar {
  const AshareTradingCalendar({
    this.closedDates = defaultClosedDates,
    this.openDates = const <String>{},
    this.updatedAt,
  });

  factory AshareTradingCalendar.fromJson(Map<String, dynamic> json) {
    return AshareTradingCalendar(
      closedDates: _dateSetFromJson(json['closedDates']) ?? defaultClosedDates,
      openDates: _dateSetFromJson(json['openDates']) ?? const <String>{},
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  static const int schemaVersion = 1;

  static const Set<String> defaultClosedDates = {
    // 2026 A-share holiday closures from SSE/SZSE annual notice.
    '2026-01-01',
    '2026-01-02',
    '2026-02-16',
    '2026-02-17',
    '2026-02-18',
    '2026-02-19',
    '2026-02-20',
    '2026-02-23',
    '2026-04-06',
    '2026-05-01',
    '2026-05-04',
    '2026-05-05',
    '2026-06-19',
    '2026-09-25',
    '2026-10-01',
    '2026-10-02',
    '2026-10-05',
    '2026-10-06',
    '2026-10-07',
  };

  static const bundled = AshareTradingCalendar();

  final Set<String> closedDates;
  final Set<String> openDates;
  final DateTime? updatedAt;

  bool isTradingDay(DateTime shanghaiMoment) {
    final key = dateKey(shanghaiMoment);
    if (openDates.contains(key)) {
      return true;
    }
    if (closedDates.contains(key)) {
      return false;
    }
    return shanghaiMoment.weekday != DateTime.saturday &&
        shanghaiMoment.weekday != DateTime.sunday;
  }

  AshareTradingCalendar copyWith({
    Set<String>? closedDates,
    Set<String>? openDates,
    DateTime? updatedAt,
  }) {
    return AshareTradingCalendar(
      closedDates: closedDates ?? this.closedDates,
      openDates: openDates ?? this.openDates,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'closedDates': _sorted(closedDates),
      'openDates': _sorted(openDates),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  static String dateKey(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static Set<String>? _dateSetFromJson(Object? value) {
    if (value is! List) {
      return null;
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where(_isDateKey)
        .toSet();
  }

  static bool _isDateKey(String value) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
  }

  static List<String> _sorted(Set<String> dates) {
    return dates.toList(growable: false)..sort();
  }
}
