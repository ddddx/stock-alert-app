import 'dart:convert';
import 'dart:io';

import '../../data/models/stock_identity.dart';
import '../../data/models/stock_quote_snapshot.dart';
import '../../data/models/stock_search_result.dart';

class AshareMarketDataService {
  AshareMarketDataService({
    HttpClient? httpClient,
    Future<dynamic> Function(Uri uri)? jsonLoader,
  })  : _httpClient = httpClient ?? HttpClient(),
        _jsonLoader = jsonLoader {
    _httpClient.connectionTimeout = const Duration(seconds: 8);
  }

  static const _searchToken = 'D43BF722C8E33BDC906FB84D85E326E8';

  final HttpClient _httpClient;
  final Future<dynamic> Function(Uri uri)? _jsonLoader;

  Future<List<StockSearchResult>> searchStocks(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    final payloads = <Map<String, dynamic>>[];
    Object? lastError;
    for (final input in _buildSearchInputs(query)) {
      try {
        payloads.add(await _fetchSearchPayload(input));
      } catch (error) {
        lastError = error;
      }
    }

    if (payloads.isEmpty && lastError != null) {
      throw lastError;
    }

    final results = <StockSearchResult>[];
    final seen = <String>{};

    for (final payload in payloads) {
      final table = payload['QuotationCodeTable'];
      final rawList =
          _extractList(table) ?? _extractList(payload['Data']) ?? const [];

      for (final item in rawList) {
        if (item is! Map) {
          continue;
        }

        final map = item.cast<String, dynamic>();
        final code = _readString(map, ['Code', 'code']);
        final name = _readString(map, ['Name', 'name']);
        final market = _guessMarket(
          code,
          _readString(map, ['MktNum', 'mktNum', 'Market', 'market']),
        );
        final securityTypeName = _readString(
          map,
          ['SecurityTypeName', 'securityTypeName', 'SecurityType'],
        );

        if (!_isSupportedSecurity(
          code: code,
          name: name,
          market: market,
          securityTypeName: securityTypeName,
        )) {
          continue;
        }

        final key = '$market-$code';
        if (!seen.add(key)) {
          continue;
        }

        results.add(
          StockSearchResult(
            code: code,
            name: name,
            market: market,
            securityTypeName: securityTypeName,
            pinyin: _readString(
              map,
              ['PinYin', 'pinYin', 'PY', 'Py', 'ShortName'],
            ),
          ),
        );
      }
    }

    return rankSearchResults(results, query);
  }

  Future<List<StockQuoteSnapshot>> fetchQuotes(
    List<StockIdentity> stocks,
  ) async {
    if (stocks.isEmpty) {
      return const [];
    }

    try {
      final batchQuotes = await _fetchBatchQuotes(stocks);
      if (batchQuotes.length == stocks.length) {
        return batchQuotes;
      }
    } catch (_) {
      // Fall back to the legacy per-stock path when the batch payload changes.
    }

    return Future.wait(stocks.map(_fetchSingleQuote));
  }

  Future<StockQuoteSnapshot> _fetchSingleQuote(StockIdentity stock) async {
    final uri = Uri.parse(
      'https://push2.eastmoney.com/api/qt/stock/get'
      '?invt=2'
      '&fltt=2'
      '&secid=${stock.secId}'
      '&fields=f57,f58,f59,f43,f169,f170,f46,f44,f45,f47,f48,f60,f18',
    );

    final payload = await _getJson(uri) as Map<String, dynamic>;
    final data = payload['data'];
    if (data is! Map) {
      throw const HttpException('Quote payload is empty');
    }

    return parseQuoteSnapshot(
      stock: stock,
      map: data.cast<String, dynamic>(),
      timestamp: DateTime.now(),
    );
  }

  Future<List<StockQuoteSnapshot>> _fetchBatchQuotes(
    List<StockIdentity> stocks,
  ) async {
    final uri = Uri.parse(
      'https://push2.eastmoney.com/api/qt/ulist.np/get'
      '?invt=2'
      '&fltt=2'
      '&fields=f12,f13,f14,f18,f57,f58,f59,f43,f169,f170,f46,f44,f45,f47,f60'
      '&secids=${stocks.map((item) => item.secId).join(',')}',
    );

    final payload = await _getJson(uri);
    if (payload is! Map<String, dynamic>) {
      throw const HttpException('Batch quote payload format is invalid');
    }

    final data = payload['data'];
    if (data is! Map) {
      throw const HttpException('Batch quote payload is empty');
    }

    final diff = data['diff'];
    if (diff is! List) {
      throw const HttpException('Batch quote list is empty');
    }

    final stockByCode = {for (final stock in stocks) stock.code: stock};
    final quotes = <StockQuoteSnapshot>[];

    for (final item in diff.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final code = _readStaticString(map, ['f57', 'f12']);
      final stock = stockByCode[code];
      if (stock == null) {
        continue;
      }

      final normalizedMap = <String, dynamic>{
        ...map,
        'f57': code,
        'f58': _readStaticString(map, ['f58', 'f14']),
        'f60': map['f60'] ?? map['f18'],
        'f170': _normalizeBatchPercent(map['f170'] ?? map['f3']),
      };

      quotes.add(
        parseQuoteSnapshot(
          stock: stock,
          map: normalizedMap,
          timestamp: DateTime.now(),
        ),
      );
    }

    if (quotes.isEmpty) {
      throw const HttpException('Batch quote list resolved to zero quotes');
    }

    quotes.sort((left, right) {
      return stocks
          .indexWhere((item) => item.code == left.code)
          .compareTo(stocks.indexWhere((item) => item.code == right.code));
    });
    return quotes;
  }

  static StockQuoteSnapshot parseQuoteSnapshot({
    required StockIdentity stock,
    required Map<String, dynamic> map,
    required DateTime timestamp,
  }) {
    final quoteCode = _readStaticString(map, ['f57']);
    final resolvedCode = quoteCode.isEmpty ? stock.code : quoteCode;
    final priceDecimalDigits = SecurityPriceScale.resolvePriceDecimalDigits(
      code: resolvedCode,
      securityTypeName: stock.securityTypeName,
      eastmoneyPriceDecimalDigits: map['f59'],
    );
    final priceDivisor = SecurityPriceScale.divisorForPriceDecimalDigits(
      priceDecimalDigits,
    ).toDouble();
    final previousClose = _scaledPrice(
              map['f60'],
              priceDivisor,
              priceDecimalDigits: priceDecimalDigits,
            ) ==
            0
        ? _scaledPrice(
            map['f18'],
            priceDivisor,
            priceDecimalDigits: priceDecimalDigits,
          )
        : _scaledPrice(
            map['f60'],
            priceDivisor,
            priceDecimalDigits: priceDecimalDigits,
          );

    return StockQuoteSnapshot(
      code: resolvedCode,
      name: _readStaticString(map, ['f58']).isEmpty
          ? stock.name
          : _readStaticString(map, ['f58']),
      market: stock.market,
      securityTypeName: stock.securityTypeName,
      priceDecimalDigits: priceDecimalDigits,
      lastPrice: _scaledPrice(
        map['f43'],
        priceDivisor,
        priceDecimalDigits: priceDecimalDigits,
      ),
      previousClose: previousClose,
      changeAmount: _scaledPrice(
        map['f169'],
        priceDivisor,
        priceDecimalDigits: priceDecimalDigits,
      ),
      changePercent: _scaledPercent(map['f170']),
      openPrice: _scaledPrice(
        map['f46'],
        priceDivisor,
        priceDecimalDigits: priceDecimalDigits,
      ),
      highPrice: _scaledPrice(
        map['f44'],
        priceDivisor,
        priceDecimalDigits: priceDecimalDigits,
      ),
      lowPrice: _scaledPrice(
        map['f45'],
        priceDivisor,
        priceDecimalDigits: priceDecimalDigits,
      ),
      volume: _plainNumber(map['f47']),
      timestamp: timestamp,
    );
  }

  Future<Map<String, dynamic>> _fetchSearchPayload(String query) async {
    final uri = Uri.parse(
      'https://searchapi.eastmoney.com/api/suggest/get'
      '?input=${Uri.encodeQueryComponent(query)}'
      '&type=14'
      '&token=$_searchToken'
      '&count=30',
    );
    final payload = await _getJson(uri);
    if (payload is! Map<String, dynamic>) {
      throw const HttpException('Search payload format is invalid');
    }
    return payload;
  }

  static List<StockSearchResult> rankSearchResults(
    List<StockSearchResult> results,
    String query,
  ) {
    final ranked =
        results.where((item) => _matchScore(item, query) > 0).toList()
          ..sort((left, right) {
            final scoreCompare =
                _matchScore(right, query).compareTo(_matchScore(left, query));
            if (scoreCompare != 0) {
              return scoreCompare;
            }

            final marketCompare = left.market.compareTo(right.market);
            if (marketCompare != 0) {
              return marketCompare;
            }

            return left.code.compareTo(right.code);
          });

    return ranked.take(20).toList(growable: false);
  }

  List<String> _buildSearchInputs(String query) {
    final variants = <String>{query};
    final normalized = _normalizeKeyword(query);
    if (normalized.isNotEmpty && normalized != query) {
      variants.add(normalized);
    }

    final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 2) {
      variants.add(digits);
    }

    return variants.toList(growable: false);
  }

  static int _matchScore(StockSearchResult result, String query) {
    final trimmedQuery = query.trim();
    final normalizedQuery = _normalizeKeyword(trimmedQuery);
    final digitQuery = normalizedQuery.replaceAll(RegExp(r'[^0-9]'), '');
    final normalizedCode = _normalizeKeyword(result.code);
    final normalizedMarketCode =
        _normalizeKeyword('${result.market}${result.code}');
    final normalizedName = _normalizeKeyword(result.name);
    final normalizedType = _normalizeKeyword(result.securityTypeName);
    final normalizedPinyin = _normalizeKeyword(result.pinyin);

    var score = 0;

    if (digitQuery.isNotEmpty) {
      if (normalizedCode == digitQuery) {
        score = 1200;
      } else if (normalizedCode.startsWith(digitQuery)) {
        score = 1000;
      } else if (normalizedCode.contains(digitQuery)) {
        score = 850;
      }

      if (normalizedMarketCode == normalizedQuery) {
        score = score < 1100 ? 1100 : score;
      } else if (normalizedMarketCode.startsWith(normalizedQuery)) {
        score = score < 920 ? 920 : score;
      }
    }

    if (normalizedName == normalizedQuery) {
      score = score < 980 ? 980 : score;
    } else if (normalizedName.startsWith(normalizedQuery)) {
      score = score < 900 ? 900 : score;
    } else if (normalizedName.contains(normalizedQuery)) {
      score = score < 780 ? 780 : score;
    }

    if (normalizedPinyin == normalizedQuery) {
      score = score < 940 ? 940 : score;
    } else if (normalizedPinyin.startsWith(normalizedQuery)) {
      score = score < 860 ? 860 : score;
    } else if (normalizedPinyin.contains(normalizedQuery)) {
      score = score < 720 ? 720 : score;
    }

    if (normalizedType.contains(normalizedQuery)) {
      score = score < 640 ? 640 : score;
    }

    if (score == 0 && trimmedQuery == result.code) {
      score = 1200;
    }

    return score;
  }

  Future<dynamic> _getJson(Uri uri) async {
    final loader = _jsonLoader;
    if (loader != null) {
      return loader(uri);
    }
    final request = await _httpClient.getUrl(uri);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/plain, */*',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    request.headers.set(
      HttpHeaders.refererHeader,
      'https://quote.eastmoney.com/',
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Request failed: ${response.statusCode}');
    }

    return jsonDecode(body);
  }

  static dynamic _normalizeBatchPercent(dynamic value) {
    if (value == null || value == '-') {
      return value;
    }
    if (value is double) {
      return value * 100;
    }
    if (value is String) {
      final trimmed = value.trim();
      final parsed = double.tryParse(trimmed);
      if (parsed != null && trimmed.contains('.')) {
        return parsed * 100;
      }
      return value;
    }
    return value;
  }

  List<dynamic>? _extractList(dynamic value) {
    if (value is List) {
      return value;
    }
    if (value is Map) {
      final map = value.cast<String, dynamic>();
      if (map['Data'] is List) {
        return map['Data'] as List<dynamic>;
      }
      if (map['data'] is List) {
        return map['data'] as List<dynamic>;
      }
    }
    return null;
  }

  String _guessMarket(String code, String rawMarket) {
    final normalizedMarket = rawMarket.toUpperCase();
    if (normalizedMarket == '1' || normalizedMarket.contains('SH')) {
      return 'SH';
    }
    if (normalizedMarket == '0' ||
        normalizedMarket == '2' ||
        normalizedMarket.contains('SZ')) {
      return 'SZ';
    }
    if (code.startsWith('5') || code.startsWith('6') || code.startsWith('9')) {
      return 'SH';
    }
    return 'SZ';
  }

  bool _isSupportedSecurity({
    required String code,
    required String name,
    required String market,
    required String securityTypeName,
  }) {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      return false;
    }
    if (market != 'SH' && market != 'SZ') {
      return false;
    }

    final normalized = _normalizeKeyword('$name $securityTypeName');
    const rejectedKeywords = [
      'HK',
      'US',
      'INDEX',
      'FUTURE',
      'OPTION',
      'FOREX',
      'REPO',
      '港股',
      '美股',
      '指数',
      '期货',
      '期权',
      '外汇',
      '回购',
    ];
    return !rejectedKeywords.any(normalized.contains);
  }

  static String _normalizeKeyword(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\.\-_/]+'), '')
        .replaceAll(RegExp(r'^(SH|SZ)'), '');
  }

  String _readString(Map<String, dynamic> map, List<String> keys) {
    return _readStaticString(map, keys);
  }

  static String _readStaticString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static double _scaledPrice(
    dynamic value,
    double divisor, {
    required int priceDecimalDigits,
  }) {
    final plain = _plainNumber(value);
    if (_isExplicitDecimalValue(value, plain, priceDecimalDigits)) {
      return plain;
    }
    return plain / divisor;
  }

  static double _scaledPercent(dynamic value) {
    return _plainNumber(value) / 100;
  }

  static double _plainNumber(dynamic value) {
    if (value == null || value == '-') {
      return 0;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString()) ?? 0;
  }

  static bool _isExplicitDecimalValue(
    dynamic rawValue,
    double plain,
    int priceDecimalDigits,
  ) {
    if (rawValue is! num && rawValue is! String) {
      return false;
    }
    if (plain == 0 || priceDecimalDigits <= 0) {
      return false;
    }
    if (rawValue is num) {
      return rawValue is double || rawValue is num && rawValue % 1 != 0;
    }
    final text = rawValue.toString().trim();
    return text.contains('.');
  }
}
