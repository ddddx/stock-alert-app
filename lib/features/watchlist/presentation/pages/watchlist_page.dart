import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/monitor_status.dart';
import '../../../../data/models/stock_identity.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/models/stock_search_result.dart';
import '../../../../data/models/watchlist_sort_order.dart';
import '../../../../data/repositories/watchlist_repository.dart';
import '../../../../services/background/monitoring_policy.dart';
import '../../../../services/market/ashare_market_data_service.dart';
import '../../../../shared/widgets/section_card.dart';
import '../watchlist_display_resolver.dart';

class WatchlistPage extends StatefulWidget {
  const WatchlistPage({
    super.key,
    required this.repository,
    required this.marketDataService,
    required this.quotes,
    required this.monitorStatus,
    required this.onRefresh,
    required this.onSortOrderChanged,
  });

  final WatchlistRepository repository;
  final AshareMarketDataService marketDataService;
  final List<StockQuoteSnapshot> quotes;
  final MonitorStatus monitorStatus;
  final Future<void> Function() onRefresh;
  final Future<void> Function(WatchlistSortOrder order) onSortOrderChanged;

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  static const _displayResolver = WatchlistDisplayResolver();

  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.repository.getAll();
    final displayItems = _displayResolver.buildItems(
      watchlist: items,
      quotes: widget.quotes,
      monitorStatus: widget.monitorStatus,
      isTradingTime: const AshareMarketHours().isTradingTime(DateTime.now()),
    );

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: '自选股',
            subtitle: '支持按代码、名称或拼音搜索。向左滑动个股可显示删除按钮。',
            trailing: Wrap(
              spacing: 8,
              children: [
                if (items.isNotEmpty)
                  IconButton.filledTonal(
                    key: const Key('watchlist-sort-button'),
                    onPressed: () async {
                      await widget.onSortOrderChanged(
                        _nextSortOrder(widget.monitorStatus.watchlistSortOrder),
                      );
                    },
                    icon: Icon(
                      _sortOrderIcon(widget.monitorStatus.watchlistSortOrder),
                    ),
                    tooltip: _sortOrderTooltip(
                      widget.monitorStatus.watchlistSortOrder,
                    ),
                  ),
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
                    child: Text('当前还没有自选股，点击“添加”开始关注股票。'),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in displayItems)
                        _WatchlistTile(
                          key: ValueKey('watchlist-${item.stock.code}'),
                          stock: item.stock,
                          quote: item.quote,
                          status: item.status,
                          onRemove: () async {
                            await widget.repository.remove(item.stock.code);
                            if (mounted) {
                              setState(() {});
                            }
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

  WatchlistSortOrder _nextSortOrder(WatchlistSortOrder order) {
    switch (order) {
      case WatchlistSortOrder.none:
        return WatchlistSortOrder.changePercentAsc;
      case WatchlistSortOrder.changePercentAsc:
        return WatchlistSortOrder.changePercentDesc;
      case WatchlistSortOrder.changePercentDesc:
        return WatchlistSortOrder.none;
    }
  }

  IconData _sortOrderIcon(WatchlistSortOrder order) {
    switch (order) {
      case WatchlistSortOrder.none:
        return Icons.sort;
      case WatchlistSortOrder.changePercentAsc:
        return Icons.trending_up;
      case WatchlistSortOrder.changePercentDesc:
        return Icons.trending_down;
    }
  }

  String _sortOrderTooltip(WatchlistSortOrder order) {
    switch (order) {
      case WatchlistSortOrder.none:
        return '排序：默认，点击切换为涨跌幅升序';
      case WatchlistSortOrder.changePercentAsc:
        return '排序：涨跌幅升序，点击切换为涨跌幅降序';
      case WatchlistSortOrder.changePercentDesc:
        return '排序：涨跌幅降序，点击切换为默认';
    }
  }
}

class _WatchlistTile extends StatefulWidget {
  const _WatchlistTile({
    super.key,
    required this.stock,
    required this.quote,
    required this.status,
    required this.onRemove,
  });

  final StockIdentity stock;
  final StockQuoteSnapshot? quote;
  final WatchlistItemStatus status;
  final Future<void> Function() onRemove;

  @override
  State<_WatchlistTile> createState() => _WatchlistTileState();
}

class _WatchlistTileState extends State<_WatchlistTile> {
  static const double _actionPanelWidth = 120;
  static const double _maxRevealOffset = _actionPanelWidth;
  double _offset = 0;

  bool get _revealed => _offset < -8;

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final positive = (quote?.changeAmount ?? 0) >= 0;
    final color = positive ? const Color(0xFFC62828) : const Color(0xFF2E7D32);
    final statusColor = switch (widget.status) {
      WatchlistItemStatus.monitoring => const Color(0xFF1565C0),
      WatchlistItemStatus.disabled => const Color(0xFF616161),
      WatchlistItemStatus.paused => const Color(0xFF6A1B9A),
      WatchlistItemStatus.offHours => const Color(0xFF546E7A),
      WatchlistItemStatus.refreshFailed => const Color(0xFFC62828),
      WatchlistItemStatus.dataAbnormal => const Color(0xFFEF6C00),
      WatchlistItemStatus.waitingRefresh => const Color(0xFF00838F),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 132,
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _revealed ? 1 : 0,
                    child: SizedBox(
                      width: _actionPanelWidth,
                      child: FilledButton.tonalIcon(
                        key: Key('watchlist-delete-${widget.stock.code}'),
                        onPressed: _revealed
                            ? () async {
                                await widget.onRemove();
                                if (!mounted) {
                                  return;
                                }
                                _close();
                              }
                            : null,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除'),
                        style: FilledButton.styleFrom(
                          foregroundColor: const Color(0xFF8B1E1E),
                          backgroundColor: const Color(0xFFFDECEC),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                offset: Offset(_offset / 320, 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _revealed ? _close : null,
                  onHorizontalDragUpdate: (details) {
                    final next = (_offset + details.delta.dx).clamp(
                      -_maxRevealOffset,
                      0.0,
                    );
                    if (next == _offset) {
                      return;
                    }
                    setState(() {
                      _offset = next;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -200 || _offset <= -_maxRevealOffset / 2) {
                      _open();
                      return;
                    }
                    _close();
                  },
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
                                widget.stock.displayName,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(widget.stock.subtitle),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  widget.status.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: statusColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _buildDetailText(quote),
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
                                      quote.lastPrice,
                                      code: quote.code,
                                      securityTypeName: quote.securityTypeName,
                                      priceDecimalDigits:
                                          quote.resolvedPriceDecimalDigits,
                                    ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              quote == null
                                  ? '--'
                                  : '${Formatters.signedPriceForSecurity(quote.changeAmount, code: quote.code, securityTypeName: quote.securityTypeName, priceDecimalDigits: quote.resolvedPriceDecimalDigits)} / ${Formatters.percent(quote.changePercent)}',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildDetailText(StockQuoteSnapshot? quote) {
    if (widget.status == WatchlistItemStatus.refreshFailed || quote == null) {
      return widget.status.detail;
    }
    if (widget.status == WatchlistItemStatus.dataAbnormal) {
      return '涨跌幅字段缺失或异常，暂不参与当前排序。';
    }
    if (widget.status == WatchlistItemStatus.disabled ||
        widget.status == WatchlistItemStatus.paused ||
        widget.status == WatchlistItemStatus.offHours) {
      return widget.status.detail;
    }
    return '今开 ${Formatters.priceForSecurity(quote.openPrice, code: quote.code, securityTypeName: quote.securityTypeName, priceDecimalDigits: quote.resolvedPriceDecimalDigits)}  最高 ${Formatters.priceForSecurity(quote.highPrice, code: quote.code, securityTypeName: quote.securityTypeName, priceDecimalDigits: quote.resolvedPriceDecimalDigits)}  最低 ${Formatters.priceForSecurity(quote.lowPrice, code: quote.code, securityTypeName: quote.securityTypeName, priceDecimalDigits: quote.resolvedPriceDecimalDigits)}';
  }

  void _open() {
    setState(() {
      _offset = -_maxRevealOffset;
    });
  }

  void _close() {
    setState(() {
      _offset = 0;
    });
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
                  '搜索A股',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '输入代码、名称或拼音',
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
        child: Text('输入关键词开始搜索股票。'),
      );
    }

    if (_loading && _results.isEmpty) {
      return const Center(
        child: Text('正在搜索...'),
      );
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Text(_error!),
      );
    }

    if (_hasSearched && _results.isEmpty) {
      return Center(
        child: Text('没有找到与“$_lastKeyword”匹配的股票。'),
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
