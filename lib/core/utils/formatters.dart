class Formatters {
  static String percent(double value, {int fractionDigits = 2}) {
    final sign = value > 0 ? '+' : value < 0 ? '-' : '';
    return '$sign${value.abs().toStringAsFixed(fractionDigits)}%';
  }

  static String price(double value) {
    return '¥${value.toStringAsFixed(2)}';
  }

  static String signedPrice(double value) {
    final sign = value > 0 ? '+' : value < 0 ? '-' : '';
    return '$sign¥${value.abs().toStringAsFixed(2)}';
  }

  static String compactDateTime(DateTime? value) {
    if (value == null) {
      return '暂无';
    }
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}
