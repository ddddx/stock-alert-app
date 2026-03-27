import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../data/models/stock_identity.dart';
import '../../data/models/stock_quote_snapshot.dart';
import '../../data/models/stock_search_result.dart';

class AshareMarketDataService {
  AshareMarketDataService({
    HttpClient? httpClient,
    Future<dynamic> Function(Uri uri)? jsonLoader,
    Future<String> Function(Uri uri)? textLoader,
    Future<void> Function(Duration delay)? sleeper,
  })  : _httpClient = httpClient ?? HttpClient(),
        _jsonLoader = jsonLoader,
        _textLoader = textLoader,
        _sleeper = sleeper ?? _defaultSleeper {
    _httpClient.connectionTimeout = const Duration(seconds: 8);
  }

  static const _searchToken = 'D43BF722C8E33BDC906FB84D85E326E8';
  static const _requestRetryBackoffs = [
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
  ];
  static const _tencentQuoteLayouts = [
    _TencentQuoteLayout(
      changeAmountIndex: 31,
      changePercentIndex: 32,
      highPriceIndex: 33,
      lowPriceIndex: 34,
      volumeIndex: 36,
    ),
    _TencentQuoteLayout(
      changeAmountIndex: 30,
      changePercentIndex: 31,
      highPriceIndex: 32,
      lowPriceIndex: 33,
      volumeIndex: 35,
    ),
  ];

  final HttpClient _httpClient;
  final Future<dynamic> Function(Uri uri)? _jsonLoader;
  final Future<String> Function(Uri uri)? _textLoader;
  final Future<void> Function(Duration delay) _sleeper;

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

  Future<List<StockQuoteSnapshot>> fetchQuotes(List<StockIdentity> stocks,
      {bool preferSingleQuoteRetrieval = false}) async {
    if (stocks.isEmpty) {
      return const [];
    }

    if (preferSingleQuoteRetrieval) {
      return _fetchQuotesIndividually(stocks);
    }

    final quotesByCode = <String, StockQuoteSnapshot>{};
    var fallbackStocks = List<StockIdentity>.from(stocks);

    try {
      final batchResult = await _fetchBatchQuotes(stocks);
      quotesByCode.addAll(batchResult.quotesByCode);
      fallbackStocks = batchResult.fallbackStocks;
    } catch (_) {
      // Fall back to the legacy per-stock path when the batch payload changes.
    }

    if (fallbackStocks.isNotEmpty) {
      _SingleQuoteOutcome? lastSingleFailure;
      final singleOutcomes = await Future.wait(
        fallbackStocks.map(_fetchSingleQuoteOutcome),
      );
      for (final outcome in singleOutcomes) {
        final quote = outcome.quote;
        if (quote != null) {
          quotesByCode[quote.code] = quote;
          continue;
        }
        lastSingleFailure = outcome;
      }

      if (quotesByCode.isEmpty && lastSingleFailure != null) {
        Error.throwWithStackTrace(
          lastSingleFailure.error!,
          lastSingleFailure.stackTrace!,
        );
      }
    }

    return stocks
        .map((stock) => quotesByCode[stock.code])
        .whereType<StockQuoteSnapshot>()
        .toList(growable: false);
  }

  Future<List<StockQuoteSnapshot>> _fetchQuotesIndividually(
    List<StockIdentity> stocks,
  ) async {
    final quotesByCode = <String, StockQuoteSnapshot>{};
    _SingleQuoteOutcome? lastSingleFailure;
    final singleOutcomes = await Future.wait(
      stocks.map(_fetchSingleQuoteOutcome),
    );
    for (final outcome in singleOutcomes) {
      final quote = outcome.quote;
      if (quote != null) {
        quotesByCode[quote.code] = quote;
        continue;
      }
      lastSingleFailure = outcome;
    }

    if (quotesByCode.isEmpty && lastSingleFailure != null) {
      Error.throwWithStackTrace(
        lastSingleFailure.error!,
        lastSingleFailure.stackTrace!,
      );
    }

    return stocks
        .map((stock) => quotesByCode[stock.code])
        .whereType<StockQuoteSnapshot>()
        .toList(growable: false);
  }

  Future<StockQuoteSnapshot> _fetchSingleQuote(StockIdentity stock) async {
    Object? eastmoneyError;
    StackTrace? eastmoneyStackTrace;
    try {
      final eastmoneyQuote = await _fetchEastmoneySingleQuote(stock);
      if (_isUsableSingleQuote(eastmoneyQuote)) {
        return eastmoneyQuote;
      }
      eastmoneyError =
          const HttpException('Eastmoney single quote is unusable');
    } catch (error, stackTrace) {
      eastmoneyError = error;
      eastmoneyStackTrace = stackTrace;
    }

    try {
      final tencentQuote = await _fetchTencentSingleQuote(stock);
      if (_isUsableSingleQuote(tencentQuote)) {
        return tencentQuote;
      }
    } catch (_) {
      // Re-throw the original Eastmoney failure when Tencent also fails.
    }

    if (eastmoneyError != null) {
      if (eastmoneyStackTrace != null) {
        Error.throwWithStackTrace(eastmoneyError, eastmoneyStackTrace);
      }
      throw eastmoneyError;
    }
    throw const HttpException('Single quote fetch failed');
  }

  Future<StockQuoteSnapshot> _fetchEastmoneySingleQuote(
      StockIdentity stock) async {
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

  Future<StockQuoteSnapshot> _fetchTencentSingleQuote(
      StockIdentity stock) async {
    final marketPrefix = stock.normalizedMarket == 'SH' ? 'sh' : 'sz';
    final uri = Uri.parse('https://qt.gtimg.cn/q=$marketPrefix${stock.code}');
    final payload = await _getText(uri);
    final fields = _parseTencentQuoteFields(payload);
    if (fields.length <= 35) {
      throw const HttpException('Tencent quote payload is incomplete');
    }

    for (final layout in _tencentQuoteLayouts) {
      final quote = _tryParseTencentSingleQuote(
        stock: stock,
        fields: fields,
        layout: layout,
      );
      if (quote != null && _isUsableSingleQuote(quote)) {
        return quote;
      }
    }

    throw const HttpException(
        'Tencent quote payload is missing numeric fields');
  }

  StockQuoteSnapshot? _tryParseTencentSingleQuote({
    required StockIdentity stock,
    required List<String> fields,
    required _TencentQuoteLayout layout,
  }) {
    final lastPrice = _parseTencentNumber(fields, 3);
    final previousClose = _parseTencentNumber(fields, 4);
    final openPrice = _parseTencentNumber(fields, 5);
    final highPrice = _parseTencentNumber(fields, layout.highPriceIndex);
    final lowPrice = _parseTencentNumber(fields, layout.lowPriceIndex);
    final changeAmount = _parseTencentNumber(fields, layout.changeAmountIndex);
    final changePercent = _parseTencentNumber(
      fields,
      layout.changePercentIndex,
    );
    final volume = _parseTencentNumber(fields, layout.volumeIndex);

    if (lastPrice == null ||
        previousClose == null ||
        openPrice == null ||
        highPrice == null ||
        lowPrice == null ||
        changeAmount == null ||
        changePercent == null ||
        volume == null) {
      return null;
    }

    return StockQuoteSnapshot(
      code: fields[2].trim().isEmpty ? stock.code : fields[2].trim(),
      name: fields[1].trim().isEmpty ? stock.name : fields[1].trim(),
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
      volume: volume,
      timestamp: DateTime.now(),
    );
  }

  Future<_SingleQuoteOutcome> _fetchSingleQuoteOutcome(
    StockIdentity stock,
  ) async {
    try {
      return _SingleQuoteOutcome.success(await _fetchSingleQuote(stock));
    } catch (error, stackTrace) {
      return _SingleQuoteOutcome.failure(error, stackTrace);
    }
  }

  Future<_BatchQuoteResult> _fetchBatchQuotes(
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
    final quotesByCode = <String, StockQuoteSnapshot>{};
    final batchTimestamp = DateTime.now();

    for (final item in diff.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final code = _readStaticString(map, ['f57', 'f12']);
      final stock = stockByCode[code];
      if (stock == null) {
        continue;
      }

      final quote = _tryParseBatchQuote(
        stock: stock,
        map: map,
        timestamp: batchTimestamp,
      );
      if (quote != null) {
        quotesByCode[stock.code] = quote;
      }
    }

    if (quotesByCode.isEmpty) {
      throw const HttpException('Batch quote list resolved to zero quotes');
    }

    final fallbackStocks =
        stocks.where((stock) => !quotesByCode.containsKey(stock.code)).toList(
              growable: false,
            );

    return _BatchQuoteResult(
      quotesByCode: quotesByCode,
      fallbackStocks: fallbackStocks,
    );
  }

  StockQuoteSnapshot? _tryParseBatchQuote({
    required StockIdentity stock,
    required Map<String, dynamic> map,
    required DateTime timestamp,
  }) {
    if (!_hasUsableBatchField(map, ['f57', 'f12']) ||
        !_hasUsableBatchNumber(map, ['f43']) ||
        !_hasUsableBatchNumber(map, ['f169']) ||
        !_hasUsableBatchNumber(map, ['f170', 'f3']) ||
        !_hasUsableBatchNumber(map, ['f46']) ||
        !_hasUsableBatchNumber(map, ['f44']) ||
        !_hasUsableBatchNumber(map, ['f45']) ||
        !_hasUsableBatchNumber(map, ['f47']) ||
        !_hasUsableBatchNumber(map, ['f60', 'f18'])) {
      return null;
    }

    final normalizedMap = <String, dynamic>{
      ...map,
      'f57': _readStaticString(map, ['f57', 'f12']),
      'f58': _readStaticString(map, ['f58', 'f14']),
      'f60': _firstUsableValue(map, ['f60', 'f18']),
      'f170': _normalizeBatchPercent(stock: stock, map: map),
    };
    if (!_hasUsableBatchNumber(normalizedMap, ['f170'])) {
      return null;
    }

    final quote = parseQuoteSnapshot(
      stock: stock,
      map: normalizedMap,
      timestamp: timestamp,
    );

    return _isSaneBatchQuote(quote) ? quote : null;
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
    for (var attempt = 0;
        attempt <= _requestRetryBackoffs.length;
        attempt += 1) {
      try {
        final loader = _jsonLoader;
        if (loader != null) {
          return await loader(uri);
        }
        return await _loadJson(uri);
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

  Future<String> _getText(Uri uri) async {
    for (var attempt = 0;
        attempt <= _requestRetryBackoffs.length;
        attempt += 1) {
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

  Future<dynamic> _loadJson(Uri uri) async {
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

  Future<String> _loadText(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'text/plain, */*');
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    request.headers.set(HttpHeaders.refererHeader, 'https://qt.gtimg.cn/');
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Request failed: ${response.statusCode}');
    }

    return latin1.decode(bytes, allowInvalid: true);
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

  static dynamic _normalizeBatchPercent({
    required StockIdentity stock,
    required Map<String, dynamic> map,
  }) {
    final rawValue = map['f170'] ?? map['f3'];
    if (rawValue == null || rawValue == '-') {
      return rawValue;
    }

    final rawPercent = _plainNumber(rawValue);
    final quoteCode = _readStaticString(map, ['f57', 'f12']);
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
              map['f60'] ?? map['f18'],
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
            map['f60'] ?? map['f18'],
            priceDivisor,
            priceDecimalDigits: priceDecimalDigits,
          );
    final changeAmount = _scaledPrice(
      map['f169'],
      priceDivisor,
      priceDecimalDigits: priceDecimalDigits,
    );

    if (previousClose == 0) {
      return rawPercent;
    }

    final expectedPercent = changeAmount / previousClose * 100;
    final directDiff = (rawPercent / 100 - expectedPercent).abs();
    final scaledDiff = (rawPercent - expectedPercent).abs();
    return scaledDiff < directDiff ? rawPercent * 100 : rawPercent;
  }

  static bool _isSaneBatchQuote(StockQuoteSnapshot quote) {
    if (quote.lastPrice <= 0 ||
        quote.previousClose <= 0 ||
        quote.openPrice < 0 ||
        quote.highPrice < 0 ||
        quote.lowPrice < 0 ||
        quote.volume < 0) {
      return false;
    }

    final tickSize = 1 / quote.priceScaleDivisor;
    final priceTolerance = tickSize * 2;
    final expectedChangeAmount = quote.lastPrice - quote.previousClose;
    if ((quote.changeAmount - expectedChangeAmount).abs() > priceTolerance) {
      return false;
    }

    if (quote.highPrice + priceTolerance < quote.lowPrice) {
      return false;
    }

    if (quote.lastPrice < quote.lowPrice - priceTolerance ||
        quote.lastPrice > quote.highPrice + priceTolerance ||
        quote.openPrice < quote.lowPrice - priceTolerance ||
        quote.openPrice > quote.highPrice + priceTolerance) {
      return false;
    }

    final expectedPercent = expectedChangeAmount / quote.previousClose * 100;
    final percentTolerance = math.max(0.35, expectedPercent.abs() * 0.1);
    if ((quote.changePercent - expectedPercent).abs() > percentTolerance) {
      return false;
    }

    return true;
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

  static bool _hasUsableBatchField(
      Map<String, dynamic> map, List<String> keys) {
    return _firstUsableValue(map, keys) != null;
  }

  static bool _hasUsableBatchNumber(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    return _tryParseFiniteNumber(_firstUsableValue(map, keys)) != null;
  }

  static dynamic _firstUsableValue(
      Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (!map.containsKey(key)) {
        continue;
      }

      final value = map[key];
      if (_isDirtyPlaceholder(value)) {
        continue;
      }

      return value;
    }
    return null;
  }

  static bool _isDirtyPlaceholder(dynamic value) {
    if (value == null) {
      return true;
    }
    if (value is! String) {
      return false;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == '-';
  }

  static double? _tryParseFiniteNumber(dynamic value) {
    if (_isDirtyPlaceholder(value)) {
      return null;
    }
    if (value is num) {
      final number = value.toDouble();
      return number.isFinite ? number : null;
    }

    final parsed = double.tryParse(value.toString().trim());
    if (parsed == null || !parsed.isFinite) {
      return null;
    }
    return parsed;
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

  static bool _isUsableSingleQuote(StockQuoteSnapshot quote) {
    if (quote.lastPrice <= 0 ||
        quote.previousClose <= 0 ||
        quote.openPrice <= 0 ||
        quote.highPrice <= 0 ||
        quote.lowPrice <= 0 ||
        quote.volume < 0) {
      return false;
    }

    final tickSize = 1 / quote.priceScaleDivisor;
    final priceTolerance = tickSize * 2;
    final expectedChangeAmount = quote.lastPrice - quote.previousClose;
    if ((quote.changeAmount - expectedChangeAmount).abs() > priceTolerance) {
      return false;
    }

    if (quote.highPrice + priceTolerance < quote.lowPrice) {
      return false;
    }

    if (quote.lastPrice < quote.lowPrice - priceTolerance ||
        quote.lastPrice > quote.highPrice + priceTolerance ||
        quote.openPrice < quote.lowPrice - priceTolerance ||
        quote.openPrice > quote.highPrice + priceTolerance) {
      return false;
    }

    final expectedPercent = expectedChangeAmount / quote.previousClose * 100;
    final percentTolerance = math.max(0.35, expectedPercent.abs() * 0.1);
    return (quote.changePercent - expectedPercent).abs() <= percentTolerance;
  }

  static List<String> _parseTencentQuoteFields(String payload) {
    final start = payload.indexOf('"');
    final end = payload.lastIndexOf('"');
    if (start < 0 || end <= start) {
      throw const HttpException('Tencent quote payload format is invalid');
    }

    return payload.substring(start + 1, end).split('~');
  }

  static double? _parseTencentNumber(List<String> fields, int index) {
    if (index >= fields.length) {
      return null;
    }
    final text = fields[index].trim();
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }
}

class _BatchQuoteResult {
  const _BatchQuoteResult({
    required this.quotesByCode,
    required this.fallbackStocks,
  });

  final Map<String, StockQuoteSnapshot> quotesByCode;
  final List<StockIdentity> fallbackStocks;
}

class _SingleQuoteOutcome {
  const _SingleQuoteOutcome.success(this.quote)
      : error = null,
        stackTrace = null;

  const _SingleQuoteOutcome.failure(this.error, this.stackTrace) : quote = null;

  final StockQuoteSnapshot? quote;
  final Object? error;
  final StackTrace? stackTrace;
}

class _TencentQuoteLayout {
  const _TencentQuoteLayout({
    required this.changeAmountIndex,
    required this.changePercentIndex,
    required this.highPriceIndex,
    required this.lowPriceIndex,
    required this.volumeIndex,
  });

  final int changeAmountIndex;
  final int changePercentIndex;
  final int highPriceIndex;
  final int lowPriceIndex;
  final int volumeIndex;
}
