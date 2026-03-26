import 'package:stock_alert_app/core/utils/formatters.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_search_result.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';

void main() {
  final checks = <String>[];

  void assertCheck(String name, bool ok, String detail) {
    checks.add('${ok ? 'PASS' : 'FAIL'} $name | $detail');
    if (!ok) {
      throw StateError(checks.join('\n'));
    }
  }

  final ashareQuote = AshareMarketDataService.parseQuoteSnapshot(
    stock: const StockIdentity(
      code: '600519',
      name: 'Moutai',
      market: 'SH',
      securityTypeName: 'AShare',
    ),
    map: const {
      'f57': '600519',
      'f58': 'Moutai',
      'f43': 12345,
      'f169': 250,
      'f170': 203,
      'f46': 12200,
      'f44': 12456,
      'f45': 12111,
      'f47': 1000,
      'f60': 12095,
      'f18': 12095,
    },
    timestamp: DateTime(2026, 1, 1, 9, 30),
  );
  assertCheck('A-share price scaling', ashareQuote.lastPrice == 123.45, '${ashareQuote.lastPrice}');

  final etfQuote = AshareMarketDataService.parseQuoteSnapshot(
    stock: const StockIdentity(
      code: '510300',
      name: 'CSI300 ETF',
      market: 'SH',
      securityTypeName: 'ETF FUND',
    ),
    map: const {
      'f57': '510300',
      'f58': 'CSI300 ETF',
      'f43': 3987,
      'f169': 15,
      'f170': 38,
      'f46': 3972,
      'f44': 3999,
      'f45': 3960,
      'f47': 2000,
      'f60': 3949,
      'f18': 3949,
    },
    timestamp: DateTime(2026, 1, 1, 9, 31),
  );
  assertCheck('ETF price scaling', etfQuote.lastPrice == 3.987, '${etfQuote.lastPrice}');
  assertCheck(
    'ETF shows three decimals',
    Formatters.priceForSecurity(
          etfQuote.lastPrice,
          code: etfQuote.code,
          securityTypeName: etfQuote.securityTypeName,
        ) ==
        '¥3.987',
    Formatters.priceForSecurity(
      etfQuote.lastPrice,
      code: etfQuote.code,
      securityTypeName: etfQuote.securityTypeName,
    ),
  );

  final bondQuote = AshareMarketDataService.parseQuoteSnapshot(
    stock: const StockIdentity(
      code: '113001',
      name: 'Convertible Bond',
      market: 'SH',
    ),
    map: const {
      'f57': '113001',
      'f58': 'Convertible Bond',
      'f43': 123456,
      'f169': 789,
      'f170': 64,
      'f46': 122500,
      'f44': 123800,
      'f45': 122100,
      'f47': 3000,
      'f60': 122667,
      'f18': 122667,
    },
    timestamp: DateTime(2026, 1, 1, 9, 32),
  );
  assertCheck('Convertible bond price scaling', bondQuote.lastPrice == 123.456, '${bondQuote.lastPrice}');

  final previewText = AlertMessageBuilder().buildPreviewText(etfQuote);
  assertCheck('Preview text uses live price', previewText.contains('¥3.987'), previewText);
  assertCheck('Preview text includes change amount', previewText.contains('+¥0.015'), previewText);

  final ranked = AshareMarketDataService.rankSearchResults(
    const [
      StockSearchResult(
        code: '516226',
        name: 'Infra ETF',
        market: 'SH',
        securityTypeName: 'ETF FUND',
      ),
      StockSearchResult(
        code: '161226',
        name: 'Silver LOF',
        market: 'SZ',
        securityTypeName: 'LOF FUND',
        pinyin: 'SILVERLOF',
      ),
      StockSearchResult(
        code: '001226',
        name: 'Fund A',
        market: 'SZ',
        securityTypeName: 'FUND',
      ),
    ],
    '161226',
  );
  assertCheck('161226 exact hit ranks first', ranked.isNotEmpty && ranked.first.code == '161226', ranked.map((e) => e.code).join(','));

  for (final line in checks) {
    print(line);
  }
}
