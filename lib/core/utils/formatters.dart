import '../../data/models/stock_identity.dart';

class Formatters {
  static String percent(double value, {int fractionDigits = 2}) {
    final sign = value > 0 ? '+' : value < 0 ? '-' : '';
    return '$sign${value.abs().toStringAsFixed(fractionDigits)}%';
  }

  static String price(double value, {int fractionDigits = 2}) {
    return '\u00A5${value.toStringAsFixed(fractionDigits)}';
  }

  static String signedPrice(double value, {int fractionDigits = 2}) {
    final sign = value > 0 ? '+' : value < 0 ? '-' : '';
    return '$sign\u00A5${value.abs().toStringAsFixed(fractionDigits)}';
  }

  static String priceForSecurity(
    double value, {
    required String code,
    String securityTypeName = '',
    int? priceDecimalDigits,
  }) {
    return price(
      value,
      fractionDigits:
          priceDecimalDigits ??
          priceFractionDigitsFor(
            code: code,
            securityTypeName: securityTypeName,
          ),
    );
  }

  static String signedPriceForSecurity(
    double value, {
    required String code,
    String securityTypeName = '',
    int? priceDecimalDigits,
  }) {
    return signedPrice(
      value,
      fractionDigits:
          priceDecimalDigits ??
          priceFractionDigitsFor(
            code: code,
            securityTypeName: securityTypeName,
          ),
    );
  }

  static int priceFractionDigitsFor({
    required String code,
    String securityTypeName = '',
  }) {
    return SecurityPriceScale.divisorFor(
              code: code,
              securityTypeName: securityTypeName,
            ) >=
            SecurityPriceScale.milliPriceDivisor
        ? 3
        : 2;
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
