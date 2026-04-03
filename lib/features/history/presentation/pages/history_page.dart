import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/stock_text_sanitizer.dart';
import '../../../../data/models/alert_history_entry.dart';
import '../../../../data/repositories/history_repository.dart';
import '../../../../data/repositories/watchlist_repository.dart';
import '../../../../shared/widgets/section_card.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.repository,
    required this.watchlistRepository,
  });

  final HistoryRepository repository;
  final WatchlistRepository watchlistRepository;

  @override
  Widget build(BuildContext context) {
    final entries = repository.getAll();
    final watchlistByCode = {
      for (final stock in watchlistRepository.getAll())
        stock.code: stock.readableName,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '\u63d0\u9192\u5386\u53f2',
          subtitle:
              '\u5c55\u793a\u89c4\u5219\u7c7b\u578b\u3001\u89e6\u53d1\u884c\u60c5\u548c\u8bed\u97f3\u64ad\u62a5\u6587\u6848\u3002',
          child: entries.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    '\u8fd8\u6ca1\u6709\u89e6\u53d1\u8bb0\u5f55\uff0c\u5148\u5237\u65b0\u51e0\u6b21\u884c\u60c5\u518d\u56de\u6765\u67e5\u770b\u3002',
                  ),
                )
              : Column(
                  children: [
                    for (final entry in entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFD),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_displayName(entry.stockCode, entry.stockName, watchlistByCode)} (${entry.stockCode})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      entry.playedSound
                                          ? '\u5df2\u64ad\u62a5'
                                          : '\u672a\u64ad\u62a5',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(_messageText(entry, watchlistByCode)),
                              const SizedBox(height: 6),
                              Text(_spokenTextLabel(entry, watchlistByCode)),
                              const SizedBox(height: 6),
                              Text(
                                '\u73b0\u4ef7 ${Formatters.priceForSecurity(entry.currentPrice, code: entry.stockCode, securityTypeName: entry.securityTypeName, priceDecimalDigits: entry.priceDecimalDigits)} / \u53c2\u8003 ${Formatters.priceForSecurity(entry.referencePrice, code: entry.stockCode, securityTypeName: entry.securityTypeName, priceDecimalDigits: entry.priceDecimalDigits)}',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '\u53d8\u52a8 ${Formatters.signedPriceForSecurity(entry.changeAmount, code: entry.stockCode, securityTypeName: entry.securityTypeName, priceDecimalDigits: entry.priceDecimalDigits)} / ${Formatters.percent(entry.changePercent)}',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '\u65f6\u95f4 ${Formatters.compactDateTime(entry.triggeredAt)}',
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _displayName(
    String stockCode,
    String stockName,
    Map<String, String> watchlistByCode,
  ) {
    final watchlistName = watchlistByCode[stockCode] ?? '';
    return StockTextSanitizer.sanitizeStockName(
      stockName,
      fallbackName: watchlistName,
      stockCode: stockCode,
    );
  }

  String _messageText(
    AlertHistoryEntry entry,
    Map<String, String> watchlistByCode,
  ) {
    final fallbackName = _displayName(
      entry.stockCode,
      entry.stockName,
      watchlistByCode,
    );
    var text = StockTextSanitizer.sanitizeReadableText(
      entry.message,
      stockCode: entry.stockCode,
      rawStockName: entry.stockName,
      fallbackStockName: fallbackName,
    );
    if (fallbackName != entry.stockCode) {
      text = text.replaceAll(entry.stockCode, fallbackName);
    }
    return text;
  }

  String _spokenTextLabel(
    AlertHistoryEntry entry,
    Map<String, String> watchlistByCode,
  ) {
    final fallbackName = _displayName(
      entry.stockCode,
      entry.stockName,
      watchlistByCode,
    );
    var spokenText = StockTextSanitizer.sanitizeReadableText(
      entry.spokenText,
      stockCode: entry.stockCode,
      rawStockName: entry.stockName,
      fallbackStockName: fallbackName,
    );
    if (fallbackName != entry.stockCode) {
      spokenText = spokenText.replaceAll(entry.stockCode, fallbackName);
    }
    return '\u64ad\u62a5\u6587\u6848\uff1a$spokenText';
  }
}
