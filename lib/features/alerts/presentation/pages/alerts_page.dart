import 'package:flutter/material.dart';

import '../../../../data/models/alert_rule.dart';
import '../../../../data/models/stock_identity.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/repositories/alert_repository.dart';
import '../../../../data/repositories/watchlist_repository.dart';
import '../../../../shared/widgets/section_card.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({
    super.key,
    required this.repository,
    required this.watchlistRepository,
    required this.quotes,
    this.onRuleUpdated,
    this.onRuleDeleted,
  });

  final AlertRepository repository;
  final WatchlistRepository watchlistRepository;
  final List<StockQuoteSnapshot> quotes;
  final Future<void> Function(AlertRule previousRule, AlertRule nextRule)?
      onRuleUpdated;
  final Future<void> Function(AlertRule rule)? onRuleDeleted;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  AlertRuleType _ruleType = AlertRuleType.shortWindowMove;
  MoveDirection _moveDirection = MoveDirection.either;
  StepMetric _stepMetric = StepMetric.percent;
  bool _applyToAllWatchlist = false;
  final Set<String> _selectedCodes = <String>{};
  late final TextEditingController _movePercentController;
  late final TextEditingController _lookbackController;
  late final TextEditingController _stepValueController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _movePercentController = TextEditingController(text: '1.00');
    _lookbackController = TextEditingController(text: '5');
    _stepValueController = TextEditingController(text: '0.50');
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _movePercentController.dispose();
    _lookbackController.dispose();
    _stepValueController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rules = widget.repository.getAll();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '提醒规则',
          subtitle: '创建、编辑和删除规则，并指定作用于选中股票或全部自选股。',
          trailing: FilledButton.icon(
            onPressed: _showAddRuleDialog,
            icon: const Icon(Icons.alarm_add_outlined),
            label: const Text('添加规则'),
          ),
          child: Column(
            children: [
              if (rules.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('还没有提醒规则，添加一条后即可开始监控。'),
                ),
              for (final rule in rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RuleCard(
                    rule: rule,
                    onToggle: (value) async {
                      await widget.repository.toggle(rule.id, value);
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    onEdit: () => _showEditRuleDialog(rule),
                    onDelete: () => _deleteRule(rule),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddRuleDialog() async {
    final watchlist = widget.watchlistRepository.getAll();
    _resetDraft(watchlist);
    await _showRuleDialog(availableStocks: watchlist);
  }

  Future<void> _showEditRuleDialog(AlertRule rule) async {
    final watchlist = widget.watchlistRepository.getAll();
    final availableStocks = _mergeAvailableStocks(
      watchlist,
      rule.resolvedTargetStocks,
    );

    _loadDraft(rule, availableStocks);
    await _showRuleDialog(
      availableStocks: availableStocks,
      existingRule: rule,
    );
  }

  Future<void> _showRuleDialog({
    required List<StockIdentity> availableStocks,
    AlertRule? existingRule,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existingRule == null ? '添加规则' : '编辑规则'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<AlertRuleType>(
                        initialValue: _ruleType,
                        items: const [
                          DropdownMenuItem(
                            value: AlertRuleType.shortWindowMove,
                            child: Text('短时波动'),
                          ),
                          DropdownMenuItem(
                            value: AlertRuleType.stepAlert,
                            child: Text('阶梯提醒'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            _ruleType = value;
                          });
                        },
                        decoration:
                            const InputDecoration(labelText: '规则类型'),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: _applyToAllWatchlist,
                        onChanged: (value) {
                          setDialogState(() {
                            _applyToAllWatchlist = value;
                            if (!value &&
                                _selectedCodes.isEmpty &&
                                availableStocks.isNotEmpty) {
                              _selectedCodes.add(availableStocks.first.code);
                            }
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        title: const Text('作用于全部自选股'),
                        subtitle: const Text(
                          '开启后，该规则会作用于当前及后续加入自选的全部股票。',
                        ),
                      ),
                      if (!_applyToAllWatchlist) ...[
                        const SizedBox(height: 8),
                        Text(
                          '目标股票',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (availableStocks.isEmpty)
                          Text(
                            '当前还没有自选股。若想先创建通用规则，请开启“作用于全部自选股”。',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFD9E1EC),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final stock in availableStocks)
                                    CheckboxListTile(
                                      dense: true,
                                      value: _selectedCodes.contains(stock.code),
                                      title: Text(stock.displayName),
                                      subtitle: Text(stock.subtitle),
                                      onChanged: (value) {
                                        setDialogState(() {
                                          if (value ?? false) {
                                            _selectedCodes.add(stock.code);
                                          } else {
                                            _selectedCodes.remove(stock.code);
                                          }
                                        });
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      if (_ruleType == AlertRuleType.shortWindowMove) ...[
                        TextField(
                          controller: _movePercentController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: '阈值涨跌幅'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _lookbackController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: '回看分钟数'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<MoveDirection>(
                          initialValue: _moveDirection,
                          items: const [
                            DropdownMenuItem(
                              value: MoveDirection.either,
                              child: Text('双向波动'),
                            ),
                            DropdownMenuItem(
                              value: MoveDirection.up,
                              child: Text('仅上涨'),
                            ),
                            DropdownMenuItem(
                              value: MoveDirection.down,
                              child: Text('仅下跌'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              _moveDirection = value;
                            });
                          },
                          decoration:
                              const InputDecoration(labelText: '方向'),
                        ),
                      ] else ...[
                        TextField(
                          controller: _stepValueController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(labelText: '阶梯步长'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<StepMetric>(
                          initialValue: _stepMetric,
                          items: const [
                            DropdownMenuItem(
                              value: StepMetric.percent,
                              child: Text('按涨跌幅阶梯'),
                            ),
                            DropdownMenuItem(
                              value: StepMetric.price,
                              child: Text('按价格阶梯'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              _stepMetric = value;
                            });
                          },
                          decoration:
                              const InputDecoration(labelText: '阶梯类型'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _stepMetric == StepMetric.percent
                              ? '例如：每多跨过一个 0.50% 的涨跌幅台阶，就再次播报一次。'
                              : '按价格阶梯提醒时，每只选中股票都会保留自己的锚定价格。',
                        ),
                        if (_stepMetric == StepMetric.price &&
                            _applyToAllWatchlist &&
                            availableStocks.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '按价格阶梯的全局规则至少需要当前已有一只自选股，应用才能记录锚定价格。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteController,
                        decoration: const InputDecoration(labelText: '备注（可选）'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final rule = _buildRule(
                      availableStocks: availableStocks,
                      existingRule: existingRule,
                    );
                    if (rule == null) {
                      _showMessage(
                        '请输入有效规则参数。定向规则至少需要选择一只股票；按价格阶梯的全局规则需要当前已有自选股。',
                      );
                      return;
                    }
                    if (existingRule == null) {
                      await widget.repository.add(rule);
                    } else {
                      await widget.repository.update(rule);
                      await widget.onRuleUpdated?.call(existingRule, rule);
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                    if (mounted) {
                      setState(() {});
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteRule(AlertRule rule) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('删除规则'),
              content: Text('确定删除这条“${rule.typeLabel}”规则吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    await widget.repository.delete(rule.id);
    await widget.onRuleDeleted?.call(rule);
    if (mounted) {
      setState(() {});
    }
  }

  void _resetDraft(List<StockIdentity> watchlist) {
    _ruleType = AlertRuleType.shortWindowMove;
    _moveDirection = MoveDirection.either;
    _stepMetric = StepMetric.percent;
    _applyToAllWatchlist = watchlist.isEmpty;
    _selectedCodes.clear();
    if (watchlist.isNotEmpty) {
      _selectedCodes.add(watchlist.first.code);
    }
    _movePercentController.text = '1.00';
    _lookbackController.text = '5';
    _stepValueController.text = '0.50';
    _noteController.clear();
  }

  void _loadDraft(AlertRule rule, List<StockIdentity> watchlist) {
    _ruleType = rule.type;
    _moveDirection = rule.moveDirection ?? MoveDirection.either;
    _stepMetric = rule.stepMetric ?? StepMetric.percent;
    _applyToAllWatchlist = rule.applyToAllWatchlist;
    _selectedCodes
      ..clear()
      ..addAll(rule.resolvedTargetStocks.map((item) => item.code));
    if (!_applyToAllWatchlist &&
        _selectedCodes.isEmpty &&
        watchlist.isNotEmpty) {
      _selectedCodes.add(watchlist.first.code);
    }
    _movePercentController.text =
        (rule.moveThresholdPercent ?? 1).toStringAsFixed(2);
    _lookbackController.text = '${rule.lookbackMinutes ?? 5}';
    _stepValueController.text = (rule.stepValue ?? 0.5).toStringAsFixed(2);
    _noteController.text = rule.note ?? '';
  }

  AlertRule? _buildRule({
    required List<StockIdentity> availableStocks,
    AlertRule? existingRule,
  }) {
    final selectedStocks = _applyToAllWatchlist
        ? availableStocks
        : availableStocks
            .where((item) => _selectedCodes.contains(item.code))
            .toList(growable: false);
    if (!_applyToAllWatchlist && selectedStocks.isEmpty) {
      return null;
    }

    if (_applyToAllWatchlist &&
        selectedStocks.isEmpty &&
        _ruleType == AlertRuleType.stepAlert &&
        _stepMetric == StepMetric.price &&
        (existingRule == null || existingRule.anchorPricesByCode.isEmpty)) {
      return null;
    }

    final primary = selectedStocks.firstOrNull ??
        existingRule?.resolvedTargetStocks.firstOrNull;
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    final id =
        existingRule?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final createdAt = existingRule?.createdAt ?? DateTime.now();
    final enabled = existingRule?.enabled ?? true;

    if (_ruleType == AlertRuleType.shortWindowMove) {
      final threshold = double.tryParse(_movePercentController.text.trim());
      final minutes = int.tryParse(_lookbackController.text.trim());
      if (threshold == null ||
          minutes == null ||
          threshold <= 0 ||
          minutes <= 0) {
        return null;
      }
      return AlertRule.shortWindowMove(
        id: id,
        stockCode: primary?.code ?? '',
        stockName: primary?.name ?? '',
        market: primary?.market ?? 'SZ',
        applyToAllWatchlist: _applyToAllWatchlist,
        targetStocks: selectedStocks,
        moveThresholdPercent: threshold,
        lookbackMinutes: minutes,
        moveDirection: _moveDirection,
        enabled: enabled,
        createdAt: createdAt,
        note: note,
      );
    }

    final stepValue = double.tryParse(_stepValueController.text.trim());
    if (stepValue == null || stepValue <= 0) {
      return null;
    }

    final anchorPrices = _stepMetric == StepMetric.price
        ? _buildAnchorPrices(selectedStocks, existingRule)
        : const <String, double>{};

    return AlertRule.stepAlert(
      id: id,
      stockCode: primary?.code ?? '',
      stockName: primary?.name ?? '',
      market: primary?.market ?? 'SZ',
      applyToAllWatchlist: _applyToAllWatchlist,
      targetStocks: selectedStocks,
      stepValue: stepValue,
      stepMetric: _stepMetric,
      enabled: enabled,
      createdAt: createdAt,
      anchorPrices: anchorPrices,
      note: note,
    );
  }

  Map<String, double> _buildAnchorPrices(
    List<StockIdentity> stocks,
    AlertRule? existingRule,
  ) {
    if (stocks.isEmpty) {
      return existingRule?.anchorPricesByCode ?? const <String, double>{};
    }

    final anchors = <String, double>{};
    for (final stock in stocks) {
      final existingAnchor = existingRule?.anchorPriceFor(stock.code);
      if (existingAnchor != null && existingAnchor > 0) {
        anchors[stock.code] = existingAnchor;
        continue;
      }

      final quote =
          widget.quotes.where((item) => item.code == stock.code).firstOrNull;
      if (quote != null && quote.lastPrice > 0) {
        anchors[stock.code] = quote.lastPrice;
      }
    }
    return anchors;
  }

  List<StockIdentity> _mergeAvailableStocks(
    List<StockIdentity> watchlist,
    List<StockIdentity> existingTargets,
  ) {
    final merged = <StockIdentity>[];
    final seen = <String>{};

    void addStocks(Iterable<StockIdentity> stocks) {
      for (final stock in stocks) {
        if (seen.add(stock.code)) {
          merged.add(stock);
        }
      }
    }

    addStocks(watchlist);
    addStocks(existingTargets);
    return merged;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final AlertRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.typeLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text('目标范围：${rule.targetsLabel()}'),
                const SizedBox(height: 4),
                Text(rule.summary),
                if (rule.note != null && rule.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(rule.note!),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: rule.enabled, onChanged: onToggle),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('edit-rule-${rule.id}'),
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '编辑',
                  ),
                  IconButton(
                    key: Key('delete-rule-${rule.id}'),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '删除',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    for (final item in this) {
      return item;
    }
    return null;
  }
}
