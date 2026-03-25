class StockIdentity {
  const StockIdentity({
    required this.code,
    required this.name,
    required this.market,
  });

  factory StockIdentity.fromJson(Map<String, dynamic> json) {
    return StockIdentity(
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      market: json['market'] as String? ?? 'SZ',
    );
  }

  String get secId => '${market == 'SH' ? '1' : '0'}.$code';
  String get displayName => '$name ($code)';

  StockIdentity copyWith({
    String? code,
    String? name,
    String? market,
  }) {
    return StockIdentity(
      code: code ?? this.code,
      name: name ?? this.name,
      market: market ?? this.market,
    );
  }

  final String code;
  final String name;
  final String market;

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'market': market,
    };
  }
}
