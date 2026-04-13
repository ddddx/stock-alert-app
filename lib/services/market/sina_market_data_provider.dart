import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../data/models/stock_identity.dart';
import '../../data/models/stock_quote_snapshot.dart';
import '../../data/models/stock_search_result.dart';
import 'ashare_market_data_service.dart';
import 'market_data_provider.dart';

class SinaMarketDataProvider extends MarketDataProvider {
  SinaMarketDataProvider({
    HttpClient? httpClient,
    Future<String> Function(Uri uri)? textLoader,
    Future<List<Map<String, dynamic>>> Function(String keyword)?
        nativeSearchLoader,
    Future<void> Function(Duration delay)? sleeper,
  })  : _httpClient = httpClient ?? HttpClient(),
        _textLoader = textLoader,
        _nativeSearchLoader = nativeSearchLoader,
        _sleeper = sleeper ?? _defaultSleeper {
    _httpClient.connectionTimeout = const Duration(seconds: 8);
  }

  static const providerIdValue = 'sina';
  static const providerNameValue = '新浪财经';
  static const _requestRetryBackoffs = [
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
  ];
  static const MethodChannel _channel = MethodChannel('stock_pulse/market');

  final HttpClient _httpClient;
  final Future<String> Function(Uri uri)? _textLoader;
  final Future<List<Map<String, dynamic>>> Function(String keyword)?
      _nativeSearchLoader;
  final Future<void> Function(Duration delay) _sleeper;

  @override
  String get providerId => providerIdValue;

  @override
  String get providerName => providerNameValue;

  @override
  Future<List<StockSearchResult>> searchStocks(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    final results = Platform.isAndroid
        ? await _searchStocksViaNative(query)
        : await _searchStocksDirectly(query);
    return AshareMarketDataService.rankSearchResults(results, query);
  }

  @override
  Future<StockQuoteSnapshot> fetchQuote(StockIdentity stock) async {
    final code = _prefixedCode(stock);
    final payload = await _getText(
      Uri.parse('https://hq.sinajs.cn/list=$code'),
    );
    final quote = _parseQuoteFromPayload(
      payload: payload,
      stockByPrefixedCode: {code: stock},
    )[stock.code];
    if (quote == null) {
      throw const HttpException('Sina quote payload is empty');
    }
    return quote;
  }

  @override
  Future<List<StockQuoteSnapshot>> fetchQuotes(
    List<StockIdentity> stocks, {
    bool preferSingleQuoteRetrieval = false,
  }) async {
    if (stocks.isEmpty) {
      return const [];
    }

    if (preferSingleQuoteRetrieval) {
      return super.fetchQuotesProgressively(
        stocks,
        preferSingleQuoteRetrieval: true,
      );
    }

    final stockByPrefixedCode = {
      for (final stock in stocks) _prefixedCode(stock): stock,
    };
    final quotesByCode = <String, StockQuoteSnapshot>{};

    try {
      final payload = await _getText(
        Uri.parse(
          'https://hq.sinajs.cn/list=${stockByPrefixedCode.keys.join(',')}',
        ),
      );
      quotesByCode.addAll(
        _parseQuoteFromPayload(
          payload: payload,
          stockByPrefixedCode: stockByPrefixedCode,
        ),
      );
    } catch (_) {
      // Fall back to per-stock retrieval when the batch payload changes.
    }

    if (quotesByCode.length < stocks.length) {
      final missingStocks = stocks
          .where((stock) => !quotesByCode.containsKey(stock.code))
          .toList(growable: false);
      final fallbackQuotes = await super.fetchQuotesProgressively(
        missingStocks,
        preferSingleQuoteRetrieval: true,
      );
      for (final quote in fallbackQuotes) {
        quotesByCode[quote.code] = quote;
      }
    }

    return stocks
        .map((stock) => quotesByCode[stock.code])
        .whereType<StockQuoteSnapshot>()
        .toList(growable: false);
  }

  Future<List<StockSearchResult>> _searchStocksViaNative(String keyword) async {
    final loader = _nativeSearchLoader;
    final payload = loader != null
        ? await loader(keyword)
        : await _invokeNativeSearch(keyword);

    return payload
        .map(_stockSearchResultFromMap)
        .whereType<StockSearchResult>()
        .toList(growable: false);
  }

  Future<List<StockSearchResult>> _searchStocksDirectly(String keyword) async {
    final payload = await _getText(
      Uri.parse(
        'https://suggest3.sinajs.cn/suggest/type=&key=${Uri.encodeQueryComponent(keyword)}',
      ),
    );
    final raw = _extractQuotedPayload(payload);
    if (raw.isEmpty) {
      return const [];
    }

    final results = <StockSearchResult>[];
    final seen = <String>{};
    for (final entry in raw.split(';')) {
      final result = _parseSearchEntry(entry);
      if (result == null) {
        continue;
      }
      final key = '${result.market}-${result.code}';
      if (!seen.add(key)) {
        continue;
      }
      results.add(result);
    }
    return results;
  }

  StockSearchResult? _stockSearchResultFromMap(Map<String, dynamic> map) {
    final code = (map['code'] as String? ?? '').trim();
    final name = (map['name'] as String? ?? '').trim();
    final market = StockIdentity.normalizeMarket(
      map['market'] as String?,
      code: code,
    );
    if (!RegExp(r'^\d{6}$').hasMatch(code) || (market != 'SH' && market != 'SZ')) {
      return null;
    }

    return StockSearchResult(
      code: code,
      name: _isReadableText(name) ? name : code,
      market: market,
      securityTypeName: (map['securityTypeName'] as String? ?? '').trim(),
      pinyin: (map['pinyin'] as String? ?? '').trim(),
    );
  }

  StockSearchResult? _parseSearchEntry(String entry) {
    final fields = entry.split(',');
    if (fields.length < 5) {
      return null;
    }

    final code = fields[2].trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      return null;
    }

    final prefixedCode = [
      if (fields.length > 3) fields[3].trim(),
      fields[0].trim(),
    ].firstWhere(
      (value) => RegExp(r'^(sh|sz)\d{6}$', caseSensitive: false).hasMatch(value),
      orElse: () => '',
    );
    if (prefixedCode.isEmpty) {
      return null;
    }

    final market = prefixedCode.toLowerCase().startsWith('sh') ? 'SH' : 'SZ';
    final rawName = [
      if (fields.length > 4) fields[4].trim(),
      if (fields.length > 6) fields[6].trim(),
    ].firstWhere(
      (value) => value.isNotEmpty,
      orElse: () => code,
    );

    return StockSearchResult(
      code: code,
      name: _isReadableText(rawName) ? rawName : code,
      market: market,
      securityTypeName: _inferSecurityTypeName(
        code: code,
        name: rawName,
        rawTypeCode: fields[1].trim(),
      ),
    );
  }

  Map<String, StockQuoteSnapshot> _parseQuoteFromPayload({
    required String payload,
    required Map<String, StockIdentity> stockByPrefixedCode,
  }) {
    final quotesByCode = <String, StockQuoteSnapshot>{};
    final matches = RegExp(
      r'var\s+hq_str_(\w+)="([^"]*)";',
      multiLine: true,
    ).allMatches(payload);

    for (final match in matches) {
      final prefixedCode = match.group(1)?.trim() ?? '';
      final stock = stockByPrefixedCode[prefixedCode];
      if (stock == null) {
        continue;
      }

      final quote = _parseQuoteFields(
        stock: stock,
        fields: match.group(2)?.split(',') ?? const [],
      );
      if (quote != null) {
        quotesByCode[quote.code] = quote;
      }
    }

    return quotesByCode;
  }

  StockQuoteSnapshot? _parseQuoteFields({
    required StockIdentity stock,
    required List<String> fields,
  }) {
    if (fields.length < 10) {
      return null;
    }

    final previousClose = _parseDouble(fields, 2);
    var lastPrice = _parseDouble(fields, 3);
    var openPrice = _parseDouble(fields, 1);
    var highPrice = _parseDouble(fields, 4);
    var lowPrice = _parseDouble(fields, 5);
    if (previousClose <= 0) {
      return null;
    }

    if (lastPrice <= 0) {
      lastPrice = previousClose;
    }
    if (openPrice <= 0) {
      openPrice = previousClose;
    }
    if (highPrice <= 0) {
      highPrice = lastPrice;
    }
    if (lowPrice <= 0) {
      lowPrice = lastPrice;
    }

    final changeAmount = lastPrice - previousClose;
    final changePercent =
        previousClose == 0 ? 0.0 : changeAmount / previousClose * 100;
    final rawName = fields[0].trim();
    final resolvedName = _isReadableText(rawName) ? rawName : stock.readableName;

    return StockQuoteSnapshot(
      code: stock.code,
      name: resolvedName,
      market: stock.market,
      securityTypeName: stock.securityTypeName,
      priceDecimalDigits: SecurityPriceScale.resolvePriceDecimalDigits(
        code: stock.code,
        securityTypeName: stock.securityTypeName,
      ),
      lastPrice: lastPrice,
      previousClose: previousClose,
      changeAmount: changeAmount,
      changePercent: changePercent,
      openPrice: openPrice,
      highPrice: highPrice,
      lowPrice: lowPrice,
      volume: _parseDouble(fields, 8),
      timestamp: _parseTimestamp(fields),
    );
  }

  DateTime _parseTimestamp(List<String> fields) {
    if (fields.length < 32) {
      return DateTime.now();
    }

    final dateText = fields[30].trim();
    final timeText = fields[31].trim();
    final dateParts = dateText.split('-');
    final timeParts = timeText.split(':');
    if (dateParts.length != 3 || timeParts.length != 3) {
      return DateTime.now();
    }

    final year = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final day = int.tryParse(dateParts[2]);
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    final second = int.tryParse(timeParts[2]);
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return DateTime.now();
    }

    return DateTime(year, month, day, hour, minute, second);
  }

  double _parseDouble(List<String> fields, int index) {
    if (index >= fields.length) {
      return 0;
    }
    return double.tryParse(fields[index].trim()) ?? 0;
  }

  String _prefixedCode(StockIdentity stock) {
    return '${stock.normalizedMarket.toLowerCase()}${stock.code}';
  }

  Future<List<Map<String, dynamic>>> _invokeNativeSearch(String keyword) async {
    try {
      final results = await _channel.invokeListMethod<dynamic>(
        'searchSinaStocks',
        {'keyword': keyword},
      );
      return (results ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(growable: false);
    } on PlatformException {
      return _searchStocksDirectly(keyword).then(
        (results) => results
            .map(
              (item) => {
                'code': item.code,
                'name': item.name,
                'market': item.market,
                'securityTypeName': item.securityTypeName,
                'pinyin': item.pinyin,
              },
            )
            .toList(growable: false),
      );
    }
  }

  Future<String> _getText(Uri uri) async {
    for (var attempt = 0; attempt <= _requestRetryBackoffs.length; attempt += 1) {
      try {
        final loader = _textLoader;
        if (loader != null) {
          return await loader(uri);
        }
        return await _loadText(uri);
      } on HttpException catch (error) {
        if (!_shouldRetryRequest(error, attempt)) {
          rethrow;
        }
      } on SocketException catch (error) {
        if (!_shouldRetryRequest(error, attempt)) {
          rethrow;
        }
      }

      await _sleeper(_requestRetryBackoffs[attempt]);
    }

    throw StateError('Unreachable retry state for $uri');
  }

  Future<String> _loadText(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*');
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    request.headers.set(HttpHeaders.refererHeader, 'https://finance.sina.com.cn');
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Request failed: ${response.statusCode}');
    }

    final charset = response.headers.contentType?.charset?.toLowerCase() ?? '';
    if (charset.contains('utf-8')) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  static String _extractQuotedPayload(String payload) {
    final start = payload.indexOf('"');
    final end = payload.lastIndexOf('"');
    if (start < 0 || end <= start) {
      return '';
    }
    return payload.substring(start + 1, end);
  }

  static Future<void> _defaultSleeper(Duration delay) {
    return Future<void>.delayed(delay);
  }

  static bool _shouldRetryRequest(Object error, int attempt) {
    if (attempt >= _requestRetryBackoffs.length) {
      return false;
    }
    if (error is SocketException) {
      return true;
    }
    if (error is! HttpException) {
      return false;
    }

    final message = error.message.toLowerCase();
    if (message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('connection terminated') ||
        message.contains('timed out') ||
        message.contains('timeout')) {
      return true;
    }

    final statusMatch = RegExp(r'request failed: (\d{3})').firstMatch(message);
    final statusCode = int.tryParse(statusMatch?.group(1) ?? '');
    return statusCode == 408 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  static bool _isReadableText(String value) {
    if (value.trim().isEmpty || RegExp(r'^\d{6}$').hasMatch(value.trim())) {
      return false;
    }
    const suspiciousFragments = ['脙', '脗', '鈧', '锟', '�'];
    return !suspiciousFragments.any(value.contains);
  }

  static String _inferSecurityTypeName({
    required String code,
    required String name,
    required String rawTypeCode,
  }) {
    final normalizedName = name.toUpperCase();
    if (normalizedName.contains('ETF')) {
      return 'ETF';
    }
    if (normalizedName.contains('LOF')) {
      return 'LOF';
    }
    if (normalizedName.contains('REIT')) {
      return 'REIT';
    }
    if (normalizedName.contains('转债') ||
        normalizedName.contains('债') ||
        RegExp(r'^(11|12)\d{4}$').hasMatch(code)) {
      return '债券';
    }
    if (rawTypeCode == '201' ||
        rawTypeCode == '203' ||
        rawTypeCode == '23' ||
        RegExp(r'^(5\d{5}|1[56]\d{4})$').hasMatch(code)) {
      return '基金';
    }
    return '股票';
  }
}
