class StockIdentity {
  const StockIdentity({
    required this.code,
    required this.name,
    required this.market,
    this.securityTypeName = '',
  });

  factory StockIdentity.fromJson(Map<String, dynamic> json) {
    final code = json['code'] as String? ?? '';
    return StockIdentity(
      code: code,
      name: json['name'] as String? ?? '',
      market: normalizeMarket(json['market'] as String?, code: code),
      securityTypeName: json['securityTypeName'] as String? ?? '',
    );
  }

  static String normalizeMarket(String? rawMarket, {String code = ''}) {
    final normalized = rawMarket?.trim().toUpperCase() ?? '';
    if (normalized.isEmpty) {
      return _inferMarketFromCode(code);
    }

    if (normalized == 'SH' ||
        normalized == '1' ||
        normalized == 'SSE' ||
        normalized == 'SHSE' ||
        normalized == 'XSHG' ||
        normalized.startsWith('SH') ||
        normalized.contains('SHANGHAI') ||
        rawMarket!.contains('沪')) {
      return 'SH';
    }

    if (normalized == 'SZ' ||
        normalized == '0' ||
        normalized == '2' ||
        normalized == 'SZSE' ||
        normalized == 'XSHE' ||
        normalized.startsWith('SZ') ||
        normalized.contains('SHENZHEN') ||
        rawMarket!.contains('深')) {
      return 'SZ';
    }

    return _inferMarketFromCode(code);
  }

  static String _inferMarketFromCode(String code) {
    final trimmedCode = code.trim();
    if (trimmedCode.startsWith('5') ||
        trimmedCode.startsWith('6') ||
        trimmedCode.startsWith('9')) {
      return 'SH';
    }
    return 'SZ';
  }

  String get normalizedMarket => normalizeMarket(market, code: code);
  String get secId => '${normalizedMarket == 'SH' ? '1' : '0'}.$code';
  String get displayName => '$name ($code)';
  String get subtitle => securityTypeName.isEmpty
      ? '$normalizedMarket 证券'
      : '$normalizedMarket 证券 · ${localizedSecurityTypeName}';
  String get localizedSecurityTypeName {
    final normalizedType = SecurityPriceScale.normalizeSecurityTypeName(
      securityTypeName,
    );
    if (normalizedType.isEmpty) {
      return '证券';
    }
    if (normalizedType.contains('ETF')) {
      return 'ETF基金';
    }
    if (normalizedType.contains('LOF')) {
      return 'LOF基金';
    }
    if (normalizedType.contains('REIT')) {
      return 'REIT基金';
    }
    if (normalizedType.contains('CONVERTIBLE') ||
        normalizedType.contains('可转债') ||
        normalizedType.contains('转债')) {
      return '可转债';
    }
    if (normalizedType.contains('BOND') || normalizedType.contains('债')) {
      return '债券';
    }
    if (normalizedType.contains('ASHARE') ||
        normalizedType.contains('STOCK') ||
        normalizedType.contains('EQUITY') ||
        normalizedType.contains('股票')) {
      return '股票';
    }
    if (normalizedType.contains('FUND') || normalizedType.contains('基金')) {
      return '基金';
    }
    return securityTypeName.trim();
  }
  int get priceScaleDivisor => SecurityPriceScale.divisorFor(
        code: code,
        securityTypeName: securityTypeName,
      );

  StockIdentity copyWith({
    String? code,
    String? name,
    String? market,
    String? securityTypeName,
  }) {
    final nextCode = code ?? this.code;
    return StockIdentity(
      code: nextCode,
      name: name ?? this.name,
      market: normalizeMarket(market ?? this.market, code: nextCode),
      securityTypeName: securityTypeName ?? this.securityTypeName,
    );
  }

  final String code;
  final String name;
  final String market;
  final String securityTypeName;

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'market': normalizedMarket,
      'securityTypeName': securityTypeName,
    };
  }
}

class SecurityPriceScale {
  static const int stockDivisor = 100;
  static const int milliPriceDivisor = 1000;

  static int resolvePriceDecimalDigits({
    required String code,
    String securityTypeName = '',
    dynamic eastmoneyPriceDecimalDigits,
  }) {
    final quoteDigits = _parsePriceDecimalDigits(eastmoneyPriceDecimalDigits);
    if (quoteDigits != null) {
      return quoteDigits;
    }
    return defaultPriceDecimalDigits(
      code: code,
      securityTypeName: securityTypeName,
    );
  }

  static int defaultPriceDecimalDigits({
    required String code,
    String securityTypeName = '',
  }) {
    return _isMilliPriceSecurity(
          code: code.trim(),
          securityTypeName: securityTypeName,
        )
        ? 3
        : 2;
  }

  static int divisorFor({
    required String code,
    String securityTypeName = '',
    dynamic quoteDecimalDigits,
    int? priceDecimalDigits,
  }) {
    final digits =
        priceDecimalDigits ??
        resolvePriceDecimalDigits(
          code: code,
          securityTypeName: securityTypeName,
          eastmoneyPriceDecimalDigits: quoteDecimalDigits,
        );
    return divisorForPriceDecimalDigits(digits);
  }

  static int divisorForPriceDecimalDigits(int digits) {
    var divisor = 1;
    for (var index = 0; index < digits; index += 1) {
      divisor *= 10;
    }
    return divisor;
  }

  static bool _isMilliPriceSecurity({
    required String code,
    required String securityTypeName,
  }) {
    if (_isLikelyFundCode(code) || _isLikelyBondCode(code)) {
      return true;
    }

    if (_isLikelyEquityCode(code)) {
      return false;
    }

    return _isMilliPriceSecurityType(_normalize(securityTypeName));
  }

  static bool _isMilliPriceSecurityType(String normalizedType) {
    if (normalizedType.isEmpty) {
      return false;
    }

    const keywords = [
      'ETF',
      'LOF',
      'FUND',
      'REIT',
      'REITS',
      '基金',
      '转债',
      '可转债',
      '债券',
      'BOND',
      'CONVERTIBLE',
    ];
    return keywords.any(normalizedType.contains);
  }

  static bool _isLikelyFundCode(String code) {
    return RegExp(r'^(5\d{5}|1[56]\d{4})$').hasMatch(code);
  }

  static bool _isLikelyBondCode(String code) {
    return RegExp(r'^(11\d{4}|12\d{4})$').hasMatch(code);
  }

  static bool _isLikelyEquityCode(String code) {
    return RegExp(
      r'^(000\d{3}|001\d{3}|002\d{3}|003\d{3}|300\d{3}|301\d{3}|600\d{3}|601\d{3}|603\d{3}|605\d{3}|688\d{3})$',
    ).hasMatch(code);
  }

  static String _normalize(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  static String normalizeSecurityTypeName(String value) => _normalize(value);

  static int? _parsePriceDecimalDigits(dynamic value) {
    final digits = switch (value) {
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value.trim()),
      _ => null,
    };
    if (digits == null || digits < 0 || digits > 6) {
      return null;
    }
    return digits;
  }
}
