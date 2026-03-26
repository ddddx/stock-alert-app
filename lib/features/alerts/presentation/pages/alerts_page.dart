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
          title: 'Rules',
          subtitle:
              'Create, edit, delete, and target rules to selected stocks or the full watchlist.',
          trailing: FilledButton.icon(
            onPressed: _showAddRuleDialog,
            icon: const Icon(Icons.alarm_add_outlined),
            label: const Text('Add rule'),
          ),
          child: Column(
            children: [
              if (rules.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No rules yet. Add one to start monitoring.'),
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
              title: Text(existingRule == null ? 'Add rule' : 'Edit rule'),
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
                            child: Text('Short-window move'),
                          ),
                          DropdownMenuItem(
                            value: AlertRuleType.stepAlert,
                            child: Text('Step alert'),
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
                            const InputDecoration(labelText: 'Rule type'),
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
                        title: const Text('Apply to the full watchlist'),
                        subtitle: const Text(
                          'When enabled, the rule applies to all current and future watchlist stocks.',
                        ),
                      ),
                      if (!_applyToAllWatchlist) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Target stocks',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (availableStocks.isEmpty)
                          Text(
                            'No watchlist stocks are available yet. Turn on "Apply to the full watchlist" to create a generic rule now.',
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
                            child: ListView(
                              shrinkWrap: true,
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
                      ],
                      const SizedBox(height: 12),
                      if (_ruleType == AlertRuleType.shortWindowMove) ...[
                        TextField(
                          controller: _movePercentController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Threshold percent'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _lookbackController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Lookback minutes'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<MoveDirection>(
                          initialValue: _moveDirection,
                          items: const [
                            DropdownMenuItem(
                              value: MoveDirection.either,
                              child: Text('Either direction'),
                            ),
                            DropdownMenuItem(
                              value: MoveDirection.up,
                              child: Text('Up only'),
                            ),
                            DropdownMenuItem(
                              value: MoveDirection.down,
                              child: Text('Down only'),
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
                              const InputDecoration(labelText: 'Direction'),
                        ),
                      ] else ...[
                        TextField(
                          controller: _stepValueController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: 'Step size'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<StepMetric>(
                          initialValue: _stepMetric,
                          items: const [
                            DropdownMenuItem(
                              value: StepMetric.percent,
                              child: Text('Percent bands'),
                            ),
                            DropdownMenuItem(
                              value: StepMetric.price,
                              child: Text('Price bands'),
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
                              const InputDecoration(labelText: 'Step type'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _stepMetric == StepMetric.percent
                              ? 'Example: speak again each time the move crosses another 0.50% band.'
                              : 'Each selected stock keeps its own anchor price when using price steps.',
                        ),
                        if (_stepMetric == StepMetric.price &&
                            _applyToAllWatchlist &&
                            availableStocks.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Price-band step rules need at least one current watchlist stock so the app can record anchor prices.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteController,
                        decoration:
                            const InputDecoration(labelText: 'Note (optional)'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final rule = _buildRule(
                      availableStocks: availableStocks,
                      existingRule: existingRule,
                    );
                    if (rule == null) {
                      _showMessage(
                        'Enter valid rule values. Targeted rules need at least one stock, and price-band global rules need a current watchlist stock.',
                      );
                      return;
                    }
                    if (existingRule == null) {
                      await widget.repository.add(rule);
                    } else {
                      await widget.repository.update(rule);
                      await widget.onRuleUpdated?.call(existingRule, rule);
                    }
                    if (mounted) {
                      setState(() {});
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Save'),
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
              title: const Text('Delete rule'),
              content: Text('Delete the ${rule.typeLabel} rule?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
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
                Text('Targets: ${rule.targetsLabel()}'),
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
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    key: Key('delete-rule-${rule.id}'),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
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
