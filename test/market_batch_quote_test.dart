import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';

void main() {
  test('fetchQuotes prefers the batch endpoint when it returns all stocks', () async {
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
  });
}
