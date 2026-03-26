import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/stock_identity.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/models/stock_search_result.dart';
import '../../../../data/repositories/watchlist_repository.dart';
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

  final WatchlistRepository repository;
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
            title: '沪深自选',
            subtitle: '支持按代码、名称或拼音自动搜索，列表展示实时行情快照。',
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
                    child: Text('还没有自选标的，点击右上角添加。'),
                  )
                : Column(
                    children: [
                      for (final item in items)
                        _WatchlistTile(
                          stock: item,
                          quote: quoteByCode[item.code],
                          onRemove: () {
                            widget.repository.remove(item.code).then((_) {
                              if (mounted) {
                                setState(() {});
                              }
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
          excludedCodes:
              widget.repository.getAll().map((item) => item.code).toSet(),
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (selected != null) {
      final added = await widget.repository.add(selected.toIdentity());
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
                  Text(stock.subtitle),
                  const SizedBox(height: 6),
                  Text(
                    quote == null
                        ? '未获取到行情，点击刷新重试。'
                        : '开 ${Formatters.priceForSecurity(quote!.openPrice, code: quote!.code, securityTypeName: quote!.securityTypeName, priceDecimalDigits: quote!.resolvedPriceDecimalDigits)}  高 ${Formatters.priceForSecurity(quote!.highPrice, code: quote!.code, securityTypeName: quote!.securityTypeName, priceDecimalDigits: quote!.resolvedPriceDecimalDigits)}  低 ${Formatters.priceForSecurity(quote!.lowPrice, code: quote!.code, securityTypeName: quote!.securityTypeName, priceDecimalDigits: quote!.resolvedPriceDecimalDigits)}',
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
                  quote == null
                      ? '--'
                      : Formatters.priceForSecurity(
                          quote!.lastPrice,
                          code: quote!.code,
                          securityTypeName: quote!.securityTypeName,
                          priceDecimalDigits: quote!.resolvedPriceDecimalDigits,
                        ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  quote == null
                      ? '--'
                      : '${Formatters.signedPriceForSecurity(quote!.changeAmount, code: quote!.code, securityTypeName: quote!.securityTypeName, priceDecimalDigits: quote!.resolvedPriceDecimalDigits)} / ${Formatters.percent(quote!.changePercent)}',
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
  Timer? _debounceTimer;
  bool _loading = false;
  bool _hasSearched = false;
  int _searchEpoch = 0;
  String _lastKeyword = '';
  String? _error;
  List<StockSearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
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
                  '搜索沪深证券',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '输入代码、名称或拼音，输入后自动搜索',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buildSuffixIcon(),
                  ),
                  onChanged: _handleQueryChanged,
                  onSubmitted: (_) => _triggerImmediateSearch(),
                ),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(child: _buildResults()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildSuffixIcon() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_controller.text.isEmpty) {
      return null;
    }
    return IconButton(
      onPressed: _clearQuery,
      icon: const Icon(Icons.close),
      tooltip: '清空',
    );
  }

  Widget _buildResults() {
    if (!_hasSearched && _controller.text.trim().isEmpty) {
      return const Center(
        child: Text('输入代码、名称或拼音后会自动搜索候选证券。'),
      );
    }

    if (_loading && _results.isEmpty) {
      return const Center(
        child: Text('正在搜索，请稍候...'),
      );
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Text(_error!),
      );
    }

    if (_hasSearched && _results.isEmpty) {
      return Center(
        child: Text('没有找到与“$_lastKeyword”匹配的沪深证券。'),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        final disabled = widget.excludedCodes.contains(item.code);
        return ListTile(
          enabled: !disabled,
          title: Text('${item.name} (${item.code})'),
          subtitle: Text(item.subtitle),
          trailing:
              disabled ? const Text('已添加') : const Icon(Icons.chevron_right),
          onTap: disabled ? null : () => Navigator.of(context).pop(item),
        );
      },
    );
  }

  void _handleQueryChanged(String value) {
    _debounceTimer?.cancel();
    _searchEpoch += 1;
    final keyword = value.trim();

    if (keyword.isEmpty) {
      setState(() {
        _loading = false;
        _hasSearched = false;
        _lastKeyword = '';
        _error = null;
        _results = const [];
      });
      return;
    }

    setState(() {
      _error = null;
      _lastKeyword = keyword;
    });

    final epoch = _searchEpoch;
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _search(keyword, epoch: epoch);
    });
  }

  Future<void> _triggerImmediateSearch() async {
    _debounceTimer?.cancel();
    final keyword = _controller.text.trim();
    _searchEpoch += 1;
    if (keyword.isEmpty) {
      setState(() {
        _loading = false;
        _hasSearched = false;
        _lastKeyword = '';
        _error = null;
        _results = const [];
      });
      return;
    }
    await _search(keyword, epoch: _searchEpoch);
  }

  Future<void> _search(String keyword, {required int epoch}) async {
    if (!mounted || epoch != _searchEpoch) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _lastKeyword = keyword;
    });

    try {
      final results = await widget.service.searchStocks(keyword);
      if (!mounted || epoch != _searchEpoch) {
        return;
      }
      setState(() {
        _loading = false;
        _hasSearched = true;
        _results = results;
      });
    } catch (error) {
      if (!mounted || epoch != _searchEpoch) {
        return;
      }
      setState(() {
        _loading = false;
        _hasSearched = true;
        _results = const [];
        _error = '搜索失败：$error';
      });
    }
  }

  void _clearQuery() {
    _debounceTimer?.cancel();
    _searchEpoch += 1;
    _controller.clear();
    setState(() {
      _loading = false;
      _hasSearched = false;
      _lastKeyword = '';
      _error = null;
      _results = const [];
    });
  }
}
