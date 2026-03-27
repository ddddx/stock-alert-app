import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';

void main() {
  test('fetchQuotes prefers the batch endpoint when it returns all stocks',
      () async {
    final uris = <Uri>[];
    final service = AshareMarketDataService(
      jsonLoader: (uri) async {
        uris.add(uri);
        return {
          'data': {
            'diff': [
              {
                'f12': '600519',
                'f14': '贵州茅台',
                'f18': 1490.0,
                'f43': 1500.0,
                'f169': 10.0,
                'f170': 67,
                'f46': 1492.0,
                'f44': 1500.0,
                'f45': 1490.0,
                'f47': 1000,
                'f59': 2,
              },
              {
                'f12': '000001',
                'f14': '平安银行',
                'f18': 10.0,
                'f43': 10.2,
                'f169': 0.2,
                'f170': 200,
                'f46': 10.0,
                'f44': 10.2,
                'f45': 9.9,
                'f47': 2000,
                'f59': 2,
              },
            ],
          },
        };
      },
    );

    final quotes = await service.fetchQuotes(const [
      StockIdentity(code: '600519', name: '贵州茅台', market: 'SH'),
      StockIdentity(code: '000001', name: '平安银行', market: 'SZ'),
    ]);

    expect(quotes, hasLength(2));
    expect(uris.single.toString(), contains('ulist.np/get'));
    expect(quotes.first.changePercent, 0.67);
    expect(quotes.last.changePercent, 2.0);
  });

  test('fetchQuotes normalizes batch percent units from both raw formats',
      () async {
    final service = AshareMarketDataService(
      jsonLoader: (uri) async {
        if (uri.toString().contains('ulist.np/get')) {
          return {
            'data': {
              'diff': [
                {
                  'f12': '600519',
                  'f14': 'Moutai',
                  'f18': 12095,
                  'f43': 12345,
                  'f169': 250,
                  'f170': 2.03,
                  'f46': 12200,
                  'f44': 12456,
                  'f45': 12111,
                  'f47': 1000,
                  'f59': 2,
                },
                {
                  'f12': '000001',
                  'f14': 'Ping An Bank',
                  'f18': 1000,
                  'f43': 1020,
                  'f169': 20,
                  'f170': 200,
                  'f46': 1000,
                  'f44': 1020,
                  'f45': 990,
                  'f47': 2000,
                  'f59': 2,
                },
              ],
            },
          };
        }
        throw StateError('unexpected uri: $uri');
      },
    );

    final quotes = await service.fetchQuotes(const [
      StockIdentity(code: '600519', name: 'Moutai', market: 'SH'),
      StockIdentity(code: '000001', name: 'Ping An Bank', market: 'SZ'),
    ]);

    expect(quotes, hasLength(2));
    expect(quotes[0].changePercent, 2.03);
    expect(quotes[1].changePercent, 2.0);
  });

  test(
      'fetchQuotes falls back to single quote when batch row has dirty placeholders',
      () async {
    final uris = <Uri>[];
    final service = AshareMarketDataService(
      jsonLoader: (uri) async {
        uris.add(uri);
        if (uri.toString().contains('ulist.np/get')) {
          return {
            'data': {
              'diff': [
                {
                  'f12': '600519',
                  'f14': 'Moutai',
                  'f18': 149000,
                  'f43': '-',
                  'f169': '-',
                  'f170': '-',
                  'f46': '-',
                  'f44': '-',
                  'f45': '-',
                  'f47': '-',
                  'f59': 2,
                },
              ],
            },
          };
        }

        expect(uri.toString(), contains('qt/stock/get'));
        expect(uri.toString(), contains('secid=1.600519'));
        return {
          'data': {
            'f57': '600519',
            'f58': 'Moutai',
            'f59': 2,
            'f43': 150000,
            'f169': 1000,
            'f170': 67,
            'f46': 149200,
            'f44': 150000,
            'f45': 149000,
            'f47': 1000,
            'f60': 149000,
            'f18': 149000,
          },
        };
      },
    );

    final quotes = await service.fetchQuotes(const [
      StockIdentity(code: '600519', name: 'Moutai', market: 'SH'),
    ]);

    expect(quotes, hasLength(1));
    expect(quotes.single.lastPrice, 1500.0);
    expect(quotes.single.changePercent, 0.67);
    expect(
      uris.where((uri) => uri.toString().contains('ulist.np/get')),
      hasLength(1),
    );
    expect(
      uris.where((uri) => uri.toString().contains('qt/stock/get')),
      hasLength(1),
    );
  });

  test(
      'fetchQuotes keeps valid batch rows and only falls back for dirty batch values',
      () async {
    final uris = <Uri>[];
    final service = AshareMarketDataService(
      jsonLoader: (uri) async {
        uris.add(uri);
        if (uri.toString().contains('ulist.np/get')) {
          return {
            'data': {
              'diff': [
                {
                  'f12': '600519',
                  'f14': 'Moutai',
                  'f18': 149000,
                  'f43': 150000,
                  'f169': 1000,
                  'f170': 10425101.0,
                  'f46': 149200,
                  'f44': 150000,
                  'f45': 149000,
                  'f47': 1000,
                  'f59': 2,
                },
                {
                  'f12': '000001',
                  'f14': 'Ping An Bank',
                  'f18': 1000,
                  'f43': 1020,
                  'f169': 20,
                  'f170': 200,
                  'f46': 1000,
                  'f44': 1020,
                  'f45': 990,
                  'f47': 2000,
                  'f59': 2,
                },
              ],
            },
          };
        }

        expect(uri.toString(), contains('qt/stock/get'));
        expect(uri.toString(), contains('secid=1.600519'));
        return {
          'data': {
            'f57': '600519',
            'f58': 'Moutai',
            'f59': 2,
            'f43': 150000,
            'f169': 1000,
            'f170': 67,
            'f46': 149200,
            'f44': 150000,
            'f45': 149000,
            'f47': 1000,
            'f60': 149000,
            'f18': 149000,
          },
        };
      },
    );

    final quotes = await service.fetchQuotes(const [
      StockIdentity(code: '600519', name: 'Moutai', market: 'SH'),
      StockIdentity(code: '000001', name: 'Ping An Bank', market: 'SZ'),
    ]);

    expect(quotes, hasLength(2));
    expect(quotes[0].code, '600519');
    expect(quotes[0].changePercent, 0.67);
    expect(quotes[1].code, '000001');
    expect(quotes[1].changePercent, 2.0);
    expect(
      uris.where((uri) => uri.toString().contains('ulist.np/get')),
      hasLength(1),
    );
    expect(
      uris.where(
        (uri) =>
            uri.toString().contains('qt/stock/get') &&
            uri.toString().contains('secid=1.600519'),
      ),
      hasLength(1),
    );
    expect(
      uris.where(
        (uri) =>
            uri.toString().contains('qt/stock/get') &&
            uri.toString().contains('secid=0.000001'),
      ),
      isEmpty,
    );
  });

  test(
      'fetchQuotes falls back only for stocks missing from an incomplete batch payload',
      () async {
    final uris = <Uri>[];
    final service = AshareMarketDataService(
      jsonLoader: (uri) async {
        uris.add(uri);
        if (uri.toString().contains('ulist.np/get')) {
          return {
            'data': {
              'diff': [
                {
                  'f12': '000001',
                  'f14': 'Ping An Bank',
                  'f18': 1000,
                  'f43': 1020,
                  'f169': 20,
                  'f170': 200,
                  'f46': 1000,
                  'f44': 1020,
                  'f45': 990,
                  'f47': 2000,
                  'f59': 2,
                },
              ],
            },
          };
        }

        expect(uri.toString(), contains('qt/stock/get'));
        expect(uri.toString(), contains('secid=1.600519'));
        return {
          'data': {
            'f57': '600519',
            'f58': 'Moutai',
            'f59': 2,
            'f43': 150000,
            'f169': 1000,
            'f170': 67,
            'f46': 149200,
            'f44': 150000,
            'f45': 149000,
            'f47': 1000,
            'f60': 149000,
            'f18': 149000,
          },
        };
      },
    );

    final quotes = await service.fetchQuotes(const [
      StockIdentity(code: '600519', name: 'Moutai', market: 'SH'),
      StockIdentity(code: '000001', name: 'Ping An Bank', market: 'SZ'),
    ]);

    expect(quotes, hasLength(2));
    expect(quotes[0].code, '600519');
    expect(quotes[0].changePercent, 0.67);
    expect(quotes[1].code, '000001');
    expect(quotes[1].changePercent, 2.0);
    expect(
      uris.where((uri) => uri.toString().contains('ulist.np/get')),
      hasLength(1),
    );
    expect(
      uris.where(
        (uri) =>
            uri.toString().contains('qt/stock/get') &&
            uri.toString().contains('secid=1.600519'),
      ),
      hasLength(1),
    );
    expect(
      uris.where(
        (uri) =>
            uri.toString().contains('qt/stock/get') &&
            uri.toString().contains('secid=0.000001'),
      ),
      isEmpty,
    );
  });

  test('fetchQuotes retries a transient single-quote failure and recovers',
      () async {
    final uris = <Uri>[];
    var singleAttempts = 0;
    var retrySleeps = 0;
    final service = AshareMarketDataService(
      sleeper: (_) async {
        retrySleeps += 1;
      },
      jsonLoader: (uri) async {
        uris.add(uri);
        if (uri.toString().contains('ulist.np/get')) {
          return {
            'data': {
              'diff': [
                {
                  'f12': '600519',
                  'f14': 'Moutai',
                  'f18': 149000,
                  'f43': '-',
                  'f169': '-',
                  'f170': '-',
                  'f46': '-',
                  'f44': '-',
                  'f45': '-',
                  'f47': '-',
                  'f59': 2,
                },
              ],
            },
          };
        }

        singleAttempts += 1;
        if (singleAttempts == 1) {
          throw const HttpException(
            'Connection closed before full header was received',
          );
        }

        return {
          'data': {
            'f57': '600519',
            'f58': 'Moutai',
            'f59': 2,
            'f43': 150000,
            'f169': 1000,
            'f170': 67,
            'f46': 149200,
            'f44': 150000,
            'f45': 149000,
            'f47': 1000,
            'f60': 149000,
            'f18': 149000,
          },
        };
      },
    );

    final quotes = await service.fetchQuotes(const [
      StockIdentity(code: '600519', name: 'Moutai', market: 'SH'),
    ]);

    expect(quotes, hasLength(1));
    expect(quotes.single.lastPrice, 1500.0);
    expect(singleAttempts, 2);
    expect(retrySleeps, 1);
    expect(
      uris.where((uri) => uri.toString().contains('ulist.np/get')),
      hasLength(1),
    );
    expect(
      uris.where((uri) => uri.toString().contains('qt/stock/get')),
      hasLength(2),
    );
  });
}
