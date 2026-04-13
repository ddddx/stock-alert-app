import '../../data/models/stock_identity.dart';
import '../../data/models/stock_quote_snapshot.dart';
import '../../data/models/stock_search_result.dart';

const defaultMarketDataProviderId = 'ashare';

abstract class MarketDataProvider {
  static const progressiveQuoteConcurrency = 4;

  String get providerId;
  String get providerName;

  Future<List<StockSearchResult>> searchStocks(String keyword);

  Future<StockQuoteSnapshot> fetchQuote(StockIdentity stock);

  Future<List<StockQuoteSnapshot>> fetchQuotes(
    List<StockIdentity> stocks, {
    bool preferSingleQuoteRetrieval = false,
  });

  Future<List<StockQuoteSnapshot>> fetchQuotesProgressively(
    List<StockIdentity> stocks, {
    void Function(StockQuoteSnapshot quote)? onQuoteReceived,
    bool preferSingleQuoteRetrieval = false,
  }) async {
    if (stocks.isEmpty) {
      return const [];
    }

    final quotesByCode = <String, StockQuoteSnapshot>{};
    final failedErrors = <Object>[];
    var nextStockIndex = 0;

    Future<void> worker() async {
      while (true) {
        final currentStockIndex = nextStockIndex;
        if (currentStockIndex >= stocks.length) {
          return;
        }
        nextStockIndex += 1;

        try {
          final quote = await fetchQuote(stocks[currentStockIndex]);
          quotesByCode[quote.code] = quote;
          onQuoteReceived?.call(quote);
        } catch (error) {
          failedErrors.add(error);
        }
      }
    }

    await Future.wait(
      List.generate(
        stocks.length < progressiveQuoteConcurrency
            ? stocks.length
            : progressiveQuoteConcurrency,
        (_) => worker(),
      ),
    );

    if (quotesByCode.isEmpty && failedErrors.isNotEmpty) {
      throw failedErrors.last;
    }

    return stocks
        .map((stock) => quotesByCode[stock.code])
        .whereType<StockQuoteSnapshot>()
        .toList(growable: false);
  }
}
