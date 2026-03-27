import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/core/utils/formatters.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/models/stock_search_result.dart';
import 'package:stock_alert_app/services/alerts/alert_message_builder.dart';
import 'package:stock_alert_app/services/market/ashare_market_data_service.dart';

void main() {
  test('ordinary A-share quotes use 100x divisor', () {
    final quote = AshareMarketDataService.parseQuoteSnapshot(
      stock: const StockIdentity(
        code: '600519',
        name: 'Moutai',
        market: 'SH',
        securityTypeName: 'AShare',
      ),
      map: const {
        'f57': '600519',
        'f58': 'Moutai',
        'f59': 2,
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

    expect(quote.lastPrice, 123.45);
    expect(quote.previousClose, 120.95);
    expect(quote.changeAmount, 2.5);
    expect(quote.changePercent, 2.03);
    expect(quote.openPrice, 122.0);
    expect(
      Formatters.priceForSecurity(
        quote.lastPrice,
        code: quote.code,
        securityTypeName: quote.securityTypeName,
        priceDecimalDigits: quote.resolvedPriceDecimalDigits,
      ),
      contains('123.45'),
    );
  });

  test('ETF type keeps milli-price divisor through search result identity', () {
    final result = const StockSearchResult(
      code: '510300',
      name: 'CSI300 ETF',
      market: 'SH',
      securityTypeName: 'ETF FUND',
    );
    final identity = result.toIdentity();
    final quote = AshareMarketDataService.parseQuoteSnapshot(
      stock: identity,
      map: const {
        'f57': '510300',
        'f58': 'CSI300 ETF',
        'f59': 3,
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

    expect(identity.securityTypeName, 'ETF FUND');
    expect(identity.priceScaleDivisor, 1000);
    expect(quote.lastPrice, 3.987);
    expect(quote.changeAmount, 0.015);
    expect(quote.changePercent, 0.38);
    expect(
      Formatters.priceForSecurity(
        quote.lastPrice,
        code: quote.code,
        securityTypeName: quote.securityTypeName,
        priceDecimalDigits: quote.resolvedPriceDecimalDigits,
      ),
      contains('3.987'),
    );
  });

  test('convertible bond code fallback uses milli-price divisor', () {
    final stock = const StockIdentity(
      code: '113001',
      name: 'Convertible Bond',
      market: 'SH',
    );
    final quote = AshareMarketDataService.parseQuoteSnapshot(
      stock: stock,
      map: const {
        'f57': '113001',
        'f58': 'Convertible Bond',
        'f59': 3,
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

    expect(stock.priceScaleDivisor, 1000);
    expect(quote.lastPrice, 123.456);
    expect(quote.changeAmount, 0.789);
    expect(quote.previousClose, 122.667);
  });

  test('equity code wins over misclassified security type', () {
    final quote = AshareMarketDataService.parseQuoteSnapshot(
      stock: const StockIdentity(
        code: '300750',
        name: 'CATL',
        market: 'SZ',
        securityTypeName: 'ETF FUND',
      ),
      map: const {
        'f57': '300750',
        'f58': 'CATL',
        'f59': 2,
        'f43': 45678,
        'f169': 123,
        'f170': 27,
        'f46': 45500,
        'f44': 45750,
        'f45': 45010,
        'f47': 3000,
        'f60': 45555,
        'f18': 45555,
      },
      timestamp: DateTime(2026, 1, 1, 9, 33),
    );

    expect(quote.securityTypeName, 'ETF FUND');
    expect(quote.priceDecimalDigits, 2);
    expect(quote.priceScaleDivisor, 100);
    expect(quote.lastPrice, 456.78);
    expect(quote.changeAmount, 1.23);
    expect(
      Formatters.priceForSecurity(
        quote.lastPrice,
        code: quote.code,
        securityTypeName: quote.securityTypeName,
        priceDecimalDigits: quote.resolvedPriceDecimalDigits,
      ),
      contains('456.78'),
    );
  });

  test('f59 overrides stale ETF milli-price scaling when quote says 2 decimals', () {
    final quote = AshareMarketDataService.parseQuoteSnapshot(
      stock: const StockIdentity(
        code: '510300',
        name: 'CSI300 ETF',
        market: 'SH',
        securityTypeName: 'ETF FUND',
      ),
      map: const {
        'f57': '510300',
        'f58': 'CSI300 ETF',
        'f59': 2,
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
      timestamp: DateTime(2026, 1, 1, 9, 34),
    );

    expect(quote.priceDecimalDigits, 2);
    expect(quote.lastPrice, 39.87);
    expect(quote.changeAmount, 0.15);
    expect(
      Formatters.priceForSecurity(
        quote.lastPrice,
        code: quote.code,
        securityTypeName: quote.securityTypeName,
        priceDecimalDigits: quote.resolvedPriceDecimalDigits,
      ),
      contains('39.87'),
    );
  });

  test('code search ranks exact six-digit hit ahead of fuzzy matches', () {
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

    expect(ranked, isNotEmpty);
    expect(ranked.first.code, '161226');
  });

  test('subtitle localizes visible security type labels to Chinese', () {
    const etf = StockIdentity(
      code: '510300',
      name: 'CSI300 ETF',
      market: 'SH',
      securityTypeName: 'ETF FUND',
    );
    const equity = StockIdentity(
      code: '600519',
      name: 'Moutai',
      market: 'SH',
      securityTypeName: 'AShare',
    );
    const bond = StockIdentity(
      code: '113001',
      name: 'Convertible Bond',
      market: 'SH',
      securityTypeName: 'CONVERTIBLE BOND',
    );

    expect(etf.subtitle, contains('ETF基金'));
    expect(equity.subtitle, contains('股票'));
    expect(bond.subtitle, contains('可转债'));
  });

  test('preview text keeps milli-price precision for ETF quotes', () {
    final quote = AshareMarketDataService.parseQuoteSnapshot(
      stock: const StockIdentity(
        code: '510300',
        name: 'CSI300 ETF',
        market: 'SH',
        securityTypeName: 'ETF FUND',
      ),
      map: const {
        'f57': '510300',
        'f58': 'CSI300 ETF',
        'f59': 3,
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

    final text = AlertMessageBuilder().buildPreviewText(quote);
    expect(text, contains('3.987'));
    expect(text, contains('+'));
    expect(text, contains('0.015'));
  });

  test('quote-side f59 overrides stale equity classification for ETF-like code', () {
    final quote = AshareMarketDataService.parseQuoteSnapshot(
      stock: const StockIdentity(
        code: '159001',
        name: 'Cross Market ETF',
        market: 'SZ',
        securityTypeName: 'AShare',
      ),
      map: const {
        'f57': '159001',
        'f58': 'Cross Market ETF',
        'f59': 3,
        'f43': 1234,
        'f169': 12,
        'f170': 98,
        'f46': 1220,
        'f44': 1245,
        'f45': 1210,
        'f47': 5000,
        'f60': 1222,
        'f18': 1222,
      },
      timestamp: DateTime(2026, 1, 1, 9, 35),
    );

    expect(quote.priceDecimalDigits, 3);
    expect(quote.lastPrice, 1.234);
    expect(quote.changeAmount, 0.012);
  });

  test('missing f59 falls back to convertible bond milli-price divisor', () {
    final quote = AshareMarketDataService.parseQuoteSnapshot(
      stock: const StockIdentity(
        code: '123001',
        name: 'Convertible Bond',
        market: 'SZ',
      ),
      map: const {
        'f57': '123001',
        'f58': 'Convertible Bond',
        'f43': 101234,
        'f169': -456,
        'f170': -45,
        'f46': 101500,
        'f44': 101900,
        'f45': 100800,
        'f47': 5000,
        'f60': 101690,
        'f18': 101690,
      },
      timestamp: DateTime(2026, 1, 1, 9, 36),
    );

    expect(quote.priceDecimalDigits, 3);
    expect(quote.lastPrice, 101.234);
    expect(quote.changeAmount, -0.456);
  });
}
