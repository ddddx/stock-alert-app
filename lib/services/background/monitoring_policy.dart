const int minMonitorPollIntervalSeconds = 1;
const int maxMonitorPollIntervalSeconds = 300;
const int minAlertCooldownSeconds = 0;
const int maxAlertCooldownSeconds = 3600;

int normalizeMonitorPollIntervalSeconds(int seconds) {
  return seconds
      .clamp(
        minMonitorPollIntervalSeconds,
        maxMonitorPollIntervalSeconds,
      )
      .toInt();
}

int normalizeAlertCooldownSeconds(int seconds) {
  return seconds
      .clamp(
        minAlertCooldownSeconds,
        maxAlertCooldownSeconds,
      )
      .toInt();
}

class AshareMarketHours {
  const AshareMarketHours();

  static const Duration _shanghaiOffset = Duration(hours: 8);
  static const int _morningSessionStartMinutes = 9 * 60 + 30;
  static const int _morningSessionEndMinutes = 11 * 60 + 30;
  static const int _afternoonSessionStartMinutes = 13 * 60;
  static const int _afternoonSessionEndMinutes = 15 * 60;

  bool isTradingTime(DateTime moment) {
    final shanghaiMoment = _toShanghaiClock(moment);
    if (_isWeekend(shanghaiMoment.weekday)) {
      return false;
    }

    final minutes = _minutesSinceMidnight(shanghaiMoment);
    final inMorningSession = minutes >= _morningSessionStartMinutes &&
        minutes < _morningSessionEndMinutes;
    final inAfternoonSession = minutes >= _afternoonSessionStartMinutes &&
        minutes < _afternoonSessionEndMinutes;
    return inMorningSession || inAfternoonSession;
  }

  DateTime nextSessionStart(DateTime moment) {
    final shanghaiMoment = _toShanghaiClock(moment);
    final nextSession = _nextSessionStartInShanghai(shanghaiMoment);
    return _fromShanghaiClock(nextSession, outputUtc: moment.isUtc);
  }

  String buildClosedMessage(DateTime moment) {
    final nextSession = _toShanghaiClock(nextSessionStart(moment));
    return '当前不在A股交易时段，监控已暂停，将于${_formatShanghaiLabel(nextSession)}恢复。';
  }

  DateTime _nextSessionStartInShanghai(DateTime shanghaiMoment) {
    if (_isWeekend(shanghaiMoment.weekday)) {
      return _nextWeekdayMorningSession(shanghaiMoment, includeToday: false);
    }

    final minutes = _minutesSinceMidnight(shanghaiMoment);
    if (minutes < _morningSessionStartMinutes) {
      return _sessionStartForDay(shanghaiMoment, hour: 9, minute: 30);
    }
    if (minutes < _morningSessionEndMinutes) {
      return shanghaiMoment;
    }
    if (minutes < _afternoonSessionStartMinutes) {
      return _sessionStartForDay(shanghaiMoment, hour: 13, minute: 0);
    }
    if (minutes < _afternoonSessionEndMinutes) {
      return shanghaiMoment;
    }
    return _nextWeekdayMorningSession(shanghaiMoment, includeToday: false);
  }

  DateTime _nextWeekdayMorningSession(
    DateTime shanghaiMoment, {
    required bool includeToday,
  }) {
    var candidate = _sessionStartForDay(shanghaiMoment, hour: 9, minute: 30);
    if (!includeToday) {
      candidate = candidate.add(const Duration(days: 1));
    }
    while (_isWeekend(candidate.weekday)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return _sessionStartForDay(candidate, hour: 9, minute: 30);
  }

  DateTime _sessionStartForDay(
    DateTime shanghaiMoment, {
    required int hour,
    required int minute,
  }) {
    return DateTime.utc(
      shanghaiMoment.year,
      shanghaiMoment.month,
      shanghaiMoment.day,
      hour,
      minute,
    );
  }

  DateTime _toShanghaiClock(DateTime moment) {
    if (moment.isUtc) {
      final shanghaiMoment = moment.add(_shanghaiOffset);
      return DateTime.utc(
        shanghaiMoment.year,
        shanghaiMoment.month,
        shanghaiMoment.day,
        shanghaiMoment.hour,
        shanghaiMoment.minute,
        shanghaiMoment.second,
        shanghaiMoment.millisecond,
        shanghaiMoment.microsecond,
      );
    }

    return DateTime.utc(
      moment.year,
      moment.month,
      moment.day,
      moment.hour,
      moment.minute,
      moment.second,
      moment.millisecond,
      moment.microsecond,
    );
  }

  DateTime _fromShanghaiClock(DateTime shanghaiMoment,
      {required bool outputUtc}) {
    if (outputUtc) {
      final utcMoment = shanghaiMoment.subtract(_shanghaiOffset);
      return DateTime.utc(
        utcMoment.year,
        utcMoment.month,
        utcMoment.day,
        utcMoment.hour,
        utcMoment.minute,
        utcMoment.second,
        utcMoment.millisecond,
        utcMoment.microsecond,
      );
    }

    return DateTime(
      shanghaiMoment.year,
      shanghaiMoment.month,
      shanghaiMoment.day,
      shanghaiMoment.hour,
      shanghaiMoment.minute,
      shanghaiMoment.second,
      shanghaiMoment.millisecond,
      shanghaiMoment.microsecond,
    );
  }

  int _minutesSinceMidnight(DateTime shanghaiMoment) {
    return shanghaiMoment.hour * 60 + shanghaiMoment.minute;
  }

  bool _isWeekend(int weekday) {
    return weekday == DateTime.saturday || weekday == DateTime.sunday;
  }

  String _formatShanghaiLabel(DateTime shanghaiMoment) {
    const weekdays = <int, String>{
      DateTime.monday: '周一',
      DateTime.tuesday: '周二',
      DateTime.wednesday: '周三',
      DateTime.thursday: '周四',
      DateTime.friday: '周五',
      DateTime.saturday: '周六',
      DateTime.sunday: '周日',
    };
    final month = _twoDigits(shanghaiMoment.month);
    final day = _twoDigits(shanghaiMoment.day);
    final hour = _twoDigits(shanghaiMoment.hour);
    final minute = _twoDigits(shanghaiMoment.minute);
    return '$month-$day ${weekdays[shanghaiMoment.weekday]} $hour:$minute';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
