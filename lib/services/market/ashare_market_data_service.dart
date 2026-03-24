import 'dart:convert';
import 'dart:io';

import '../../data/models/stock_identity.dart';
import '../../data/models/stock_quote_snapshot.dart';
import '../../data/models/stock_search_result.dart';

class AshareMarketDataService {
  static const _searchToken = 'D43BF722C8E33BDC906FB84D85E326E8';

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  Future<List<StockSearchResult>> searchStocks(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    final uri = Uri.parse(
      'https://searchapi.eastmoney.com/api/suggest/get'
      '?input=${Uri.encodeQueryComponent(query)}'
      '&type=14'
      '&token=$_searchToken'
      '&count=10',
    );

    final payload = await _getJson(uri) as Map<String, dynamic>;
    final table = payload['QuotationCodeTable'];
    final rawList = _extractList(table) ?? _extractList(payload['Data']) ?? const [];
    final results = <StockSearchResult>[];
    final seen = <String>{};

    for (final item in rawList) {
      if (item is! Map) {
        continue;
      }
      final map = item.cast<String, dynamic>();
      final code = _readString(map, ['Code', 'code']);
      final name = _readString(map, ['Name', 'name']);
      final market = _guessMarket(code, _readString(map, ['MktNum', 'mktNum']));
      final securityTypeName = _readString(
        map,
        ['SecurityTypeName', 'securityTypeName', 'SecurityType'],
      );

      if (!_isAshare(code: code, market: market, securityTypeName: securityTypeName)) {
        continue;
      }

      final key = '$market-$code';
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);

      results.add(
        StockSearchResult(
          code: code,
          name: name,
          market: market,
          securityTypeName: securityTypeName,
          pinyin: _readString(map, ['PinYin', 'pinYin']),
        ),
      );
    }

    return results;
  }

  Future<List<StockQuoteSnapshot>> fetchQuotes(List<StockIdentity> stocks) async {
    if (stocks.isEmpty) {
      return const [];
    }

    return Future.wait(stocks.map(_fetchSingleQuote));
  }

  Future<StockQuoteSnapshot> _fetchSingleQuote(StockIdentity stock) async {
    final uri = Uri.parse(
      'https://push2.eastmoney.com/api/qt/stock/get'
      '?invt=2'
      '&fltt=2'
      '&secid=${stock.secId}'
      '&fields=f57,f58,f43,f169,f170,f46,f44,f45,f47,f48,f60,f18',
    );

    final payload = await _getJson(uri) as Map<String, dynamic>;
    final data = payload['data'];
    if (data is! Map) {
      throw const HttpException('行情接口返回为空');
    }

    final map = data.cast<String, dynamic>();
    final previousClose = _scaledNumber(map['f60']) == 0
        ? _scaledNumber(map['f18'])
        : _scaledNumber(map['f60']);

    return StockQuoteSnapshot(
      code: _readString(map, ['f57']).isEmpty ? stock.code : _readString(map, ['f57']),
      name: _readString(map, ['f58']).isEmpty ? stock.name : _readString(map, ['f58']),
      market: stock.market,
      lastPrice: _scaledNumber(map['f43']),
      previousClose: previousClose,
      changeAmount: _scaledNumber(map['f169']),
      changePercent: _scaledNumber(map['f170']),
      openPrice: _scaledNumber(map['f46']),
      highPrice: _scaledNumber(map['f44']),
      lowPrice: _scaledNumber(map['f45']),
      volume: _plainNumber(map['f47']),
      timestamp: DateTime.now(),
    );
  }

  Future<dynamic> _getJson(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*');
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    request.headers.set(HttpHeaders.refererHeader, 'https://quote.eastmoney.com/');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('接口请求失败: ${response.statusCode}');
    }

    return jsonDecode(body);
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
    if (code.startsWith('6')) {
      return 'SH';
    }
    if (code.startsWith('0') || code.startsWith('3')) {
      return 'SZ';
    }
    if (rawMarket == '1') {
      return 'SH';
    }
    return 'SZ';
  }

  bool _isAshare({
    required String code,
    required String market,
    required String securityTypeName,
  }) {
    final codePattern = RegExp(r'^(0|3|6)\d{5}$');
    if (!codePattern.hasMatch(code)) {
      return false;
    }
    if (market != 'SH' && market != 'SZ') {
      return false;
    }
    final lowerType = securityTypeName.toLowerCase();
    const rejected = ['港', 'hk', '美', 'us', '基金', '债', '期货', '指数'];
    return !rejected.any(lowerType.contains);
  }

  String _readString(Map<String, dynamic> map, List<String> keys) {
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

  double _scaledNumber(dynamic value) {
    return _plainNumber(value) / 100;
  }

  double _plainNumber(dynamic value) {
    if (value == null || value == '-') {
      return 0;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString()) ?? 0;
  }
}
