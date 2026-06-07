import '../../data/models/stock_identity.dart';
import '../../data/models/market_sentiment_snapshot.dart';
import '../../data/models/stock_quote_snapshot.dart';
import '../../data/models/stock_search_result.dart';

const defaultMarketDataProviderId = 'ashare';

class MarketDataFetchStatus {
  const MarketDataFetchStatus({
    this.requestedCount = 0,
    this.successCount = 0,
    this.failedCount = 0,
    this.fallbackUsed = false,
    this.lastError = '',
  });

  final int requestedCount;
  final int successCount;
  final int failedCount;
  final bool fallbackUsed;
  final String lastError;
}

abstract class MarketDataProvider {
  static const progressiveQuoteConcurrency = 4;

  MarketDataFetchStatus _lastFetchStatus = const MarketDataFetchStatus();

  String get providerId;
  String get providerName;
  MarketDataFetchStatus get lastFetchStatus => _lastFetchStatus;

  void markFetchStatus(MarketDataFetchStatus status) {
    _lastFetchStatus = status;
  }

  Future<List<StockSearchResult>> searchStocks(String keyword);

  Future<MarketSentimentSnapshot> fetchMarketSentiment();

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
      markFetchStatus(const MarketDataFetchStatus());
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
      markFetchStatus(
        MarketDataFetchStatus(
          requestedCount: stocks.length,
          successCount: 0,
          failedCount: stocks.length,
          lastError: failedErrors.last.toString(),
        ),
      );
      throw failedErrors.last;
    }

    final quotes = stocks
        .map((stock) => quotesByCode[stock.code])
        .whereType<StockQuoteSnapshot>()
        .toList(growable: false);
    markFetchStatus(
      MarketDataFetchStatus(
        requestedCount: stocks.length,
        successCount: quotes.length,
        failedCount: stocks.length - quotes.length,
        lastError: failedErrors.isEmpty ? '' : failedErrors.last.toString(),
      ),
    );
    return quotes;
  }
}
