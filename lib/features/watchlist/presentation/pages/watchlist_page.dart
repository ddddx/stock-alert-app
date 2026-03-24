import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/stock_identity.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/models/stock_search_result.dart';
import '../../../../data/repositories/in_memory_watchlist_repository.dart';
import '../../../../services/market/ashare_market_data_service.dart';
import '../../../../shared/widgets/section_card.dart';

class WatchlistPage extends StatefulWidget {
  const WatchlistPage({
    super.key,
    required this.repository,
    required this.marketDataService,
    required this.quotes,
    required this.onRefresh,
  });

  final InMemoryWatchlistRepository repository;
  final AshareMarketDataService marketDataService;
  final List<StockQuoteSnapshot> quotes;
  final Future<void> Function() onRefresh;

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.repository.getAll();
    final quoteByCode = {for (final quote in widget.quotes) quote.code: quote};

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'A股自选',
            subtitle: '支持按代码或名称模糊搜索，列表展示实时行情快照。',
            trailing: Wrap(
              spacing: 8,
              children: [
                IconButton.filledTonal(
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新行情',
                ),
                FilledButton.icon(
                  onPressed: _adding ? null : _showAddSheet,
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('还没有自选股票，点击右上角添加。'),
                  )
                : Column(
                    children: [
                      for (final item in items)
                        _WatchlistTile(
                          stock: item,
                          quote: quoteByCode[item.code],
                          onRemove: () {
                            setState(() {
                              widget.repository.remove(item.code);
                            });
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddSheet() async {
    setState(() {
      _adding = true;
    });

    final selected = await showModalBottomSheet<StockSearchResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _StockSearchSheet(
          service: widget.marketDataService,
          excludedCodes: widget.repository.getAll().map((item) => item.code).toSet(),
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (selected != null) {
      final added = widget.repository.add(selected.toIdentity());
      if (added) {
        await widget.onRefresh();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 ${selected.name} ${selected.code}')),
        );
      }
      setState(() {});
    }

    setState(() {
      _adding = false;
    });
  }
}

class _WatchlistTile extends StatelessWidget {
  const _WatchlistTile({
    required this.stock,
    required this.quote,
    required this.onRemove,
  });

  final StockIdentity stock;
  final StockQuoteSnapshot? quote;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final positive = (quote?.changeAmount ?? 0) >= 0;
    final color = positive ? const Color(0xFFC62828) : const Color(0xFF2E7D32);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stock.displayName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text('${stock.market} A股'),
                  const SizedBox(height: 6),
                  Text(
                    quote == null
                        ? '未获取到行情，点击刷新重试'
                        : '开 ${Formatters.price(quote!.openPrice)}  高 ${Formatters.price(quote!.highPrice)}  低 ${Formatters.price(quote!.lowPrice)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  quote == null ? '--' : Formatters.price(quote!.lastPrice),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  quote == null
                      ? '--'
                      : '${Formatters.signedPrice(quote!.changeAmount)} / ${Formatters.percent(quote!.changePercent)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              tooltip: '移除',
            ),
          ],
        ),
      ),
    );
  }
}

class _StockSearchSheet extends StatefulWidget {
  const _StockSearchSheet({
    required this.service,
    required this.excludedCodes,
  });

  final AshareMarketDataService service;
  final Set<String> excludedCodes;

  @override
  State<_StockSearchSheet> createState() => _StockSearchSheetState();
}

class _StockSearchSheetState extends State<_StockSearchSheet> {
  late final TextEditingController _controller;
  bool _loading = false;
  String? _error;
  List<StockSearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SizedBox(
          height: 520,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '搜索 A 股',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '输入股票代码、名称或拼音缩写',
                    suffixIcon: IconButton(
                      onPressed: _loading ? null : _search,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_loading) const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Expanded(
                  child: _results.isEmpty
                      ? const Center(
                          child: Text('输入关键字后搜索候选股票。'),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            final disabled = widget.excludedCodes.contains(item.code);
                            return ListTile(
                              enabled: !disabled,
                              title: Text('${item.name} (${item.code})'),
                              subtitle: Text(item.subtitle),
                              trailing: disabled
                                  ? const Text('已添加')
                                  : const Icon(Icons.chevron_right),
                              onTap: disabled
                                  ? null
                                  : () => Navigator.of(context).pop(item),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _results = const [];
        _error = '请输入代码、名称或拼音缩写。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await widget.service.searchStocks(keyword);
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        if (results.isEmpty) {
          _error = '没有找到匹配的 A 股候选。';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const [];
        _error = '搜索失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }
}
