import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../data/repositories/history_repository.dart';
import '../../../../shared/widgets/section_card.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.repository});

  final HistoryRepository repository;

  @override
  Widget build(BuildContext context) {
    final entries = repository.getAll();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '提醒历史',
          subtitle: '展示规则类型、触发行情和语音播报文案。',
          child: entries.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('还没有触发记录，先刷新几次行情再回来查看。'),
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
                                      '${entry.stockName} (${entry.stockCode})',
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                  ),
                                  Chip(
                                    label: Text(entry.playedSound ? '已播报' : '未播报'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(entry.message),
                              const SizedBox(height: 6),
                              Text('播报文案：${entry.spokenText}'),
                              const SizedBox(height: 6),
                              Text(
                                '现价 ${Formatters.priceForSecurity(entry.currentPrice, code: entry.stockCode, securityTypeName: entry.securityTypeName, priceDecimalDigits: entry.priceDecimalDigits)} / 参考 ${Formatters.priceForSecurity(entry.referencePrice, code: entry.stockCode, securityTypeName: entry.securityTypeName, priceDecimalDigits: entry.priceDecimalDigits)}',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '变动 ${Formatters.signedPriceForSecurity(entry.changeAmount, code: entry.stockCode, securityTypeName: entry.securityTypeName, priceDecimalDigits: entry.priceDecimalDigits)} / ${Formatters.percent(entry.changePercent)}',
                              ),
                              const SizedBox(height: 6),
                              Text('时间 ${Formatters.compactDateTime(entry.triggeredAt)}'),
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
}
