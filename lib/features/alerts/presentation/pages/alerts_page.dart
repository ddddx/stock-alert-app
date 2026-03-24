import 'package:flutter/material.dart';

import '../../../../data/models/alert_rule.dart';
import '../../../../data/models/stock_identity.dart';
import '../../../../data/models/stock_quote_snapshot.dart';
import '../../../../data/repositories/in_memory_alert_repository.dart';
import '../../../../data/repositories/in_memory_watchlist_repository.dart';
import '../../../../shared/widgets/section_card.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({
    super.key,
    required this.repository,
    required this.watchlistRepository,
    required this.quotes,
  });

  final InMemoryAlertRepository repository;
  final InMemoryWatchlistRepository watchlistRepository;
  final List<StockQuoteSnapshot> quotes;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  AlertRuleType _ruleType = AlertRuleType.shortWindowMove;
  MoveDirection _moveDirection = MoveDirection.either;
  StepMetric _stepMetric = StepMetric.percent;
  late final TextEditingController _movePercentController;
  late final TextEditingController _lookbackController;
  late final TextEditingController _stepValueController;
  late final TextEditingController _noteController;
  String? _selectedCode;

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
          subtitle: '支持短时大幅波动和台阶提醒两类规则。',
          trailing: FilledButton.icon(
            onPressed: _showAddRuleDialog,
            icon: const Icon(Icons.alarm_add_outlined),
            label: const Text('新增规则'),
          ),
          child: Column(
            children: [
              if (rules.isEmpty) const Text('暂无规则，先为自选股票添加一条。'),
              for (final rule in rules)
                Padding(
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
                                '${rule.stockName} (${rule.stockCode})',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(rule.typeLabel),
                              const SizedBox(height: 4),
                              Text(rule.summary),
                              if (rule.note != null && rule.note!.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(rule.note!),
                              ],
                            ],
                          ),
                        ),
                        Switch(
                          value: rule.enabled,
                          onChanged: (value) {
                            setState(() {
                              widget.repository.toggle(rule.id, value);
                            });
                          },
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

  Future<void> _showAddRuleDialog() async {
    final watchlist = widget.watchlistRepository.getAll();
    if (watchlist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在自选页添加股票。')),
      );
      return;
    }

    _selectedCode = watchlist.first.code;
    _ruleType = AlertRuleType.shortWindowMove;
    _moveDirection = MoveDirection.either;
    _stepMetric = StepMetric.percent;
    _movePercentController.text = '1.00';
    _lookbackController.text = '5';
    _stepValueController.text = '0.50';
    _noteController.clear();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selected = watchlist.firstWhere(
              (item) => item.code == _selectedCode,
              orElse: () => watchlist.first,
            );

            return AlertDialog(
              title: const Text('新增提醒规则'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCode,
                      items: [
                        for (final stock in watchlist)
                          DropdownMenuItem(
                            value: stock.code,
                            child: Text(stock.displayName),
                          ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedCode = value;
                        });
                      },
                      decoration: const InputDecoration(labelText: '股票'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AlertRuleType>(
                      initialValue: _ruleType,
                      items: const [
                        DropdownMenuItem(
                          value: AlertRuleType.shortWindowMove,
                          child: Text('短时大幅波动'),
                        ),
                        DropdownMenuItem(
                          value: AlertRuleType.stepAlert,
                          child: Text('台阶提醒'),
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
                      decoration: const InputDecoration(labelText: '规则类型'),
                    ),
                    const SizedBox(height: 12),
                    if (_ruleType == AlertRuleType.shortWindowMove) ...[
                      TextField(
                        controller: _movePercentController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '波动阈值 %'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _lookbackController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '时间窗口 分钟'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<MoveDirection>(
                        initialValue: _moveDirection,
                        items: const [
                          DropdownMenuItem(
                            value: MoveDirection.either,
                            child: Text('涨跌都提醒'),
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
                        decoration: const InputDecoration(labelText: '方向'),
                      ),
                    ] else ...[
                      TextField(
                        controller: _stepValueController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '台阶大小'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<StepMetric>(
                        initialValue: _stepMetric,
                        items: const [
                          DropdownMenuItem(
                            value: StepMetric.percent,
                            child: Text('按涨跌幅台阶'),
                          ),
                          DropdownMenuItem(
                            value: StepMetric.price,
                            child: Text('按价格台阶'),
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
                        decoration: const InputDecoration(labelText: '台阶类型'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _stepMetric == StepMetric.percent
                            ? '示例：每跨过 0.50% 涨跌幅台阶提醒一次。'
                            : '示例：以创建时价格为锚点，每跨过固定价差提醒一次。',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(labelText: '备注（可选）'),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '当前股票：${selected.displayName}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final stock = watchlist.firstWhere(
                      (item) => item.code == _selectedCode,
                      orElse: () => watchlist.first,
                    );
                    final rule = _buildRule(stock);
                    if (rule == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请填写有效的规则参数。')),
                      );
                      return;
                    }
                    setState(() {
                      widget.repository.add(rule);
                    });
                    Navigator.of(context).pop();
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

  AlertRule? _buildRule(StockIdentity stock) {
    if (_ruleType == AlertRuleType.shortWindowMove) {
      final threshold = double.tryParse(_movePercentController.text.trim());
      final minutes = int.tryParse(_lookbackController.text.trim());
      if (threshold == null || minutes == null || threshold <= 0 || minutes <= 0) {
        return null;
      }
      return AlertRule.shortWindowMove(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        stockCode: stock.code,
        stockName: stock.name,
        market: stock.market,
        moveThresholdPercent: threshold,
        lookbackMinutes: minutes,
        moveDirection: _moveDirection,
        enabled: true,
        createdAt: DateTime.now(),
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
    }

    final stepValue = double.tryParse(_stepValueController.text.trim());
    if (stepValue == null || stepValue <= 0) {
      return null;
    }

    final quote = widget.quotes.where((item) => item.code == stock.code).firstOrNull;
    return AlertRule.stepAlert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      stockCode: stock.code,
      stockName: stock.name,
      market: stock.market,
      stepValue: stepValue,
      stepMetric: _stepMetric,
      enabled: true,
      createdAt: DateTime.now(),
      anchorPrice: _stepMetric == StepMetric.price ? quote?.lastPrice : null,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );
  }
}

extension on Iterable<StockQuoteSnapshot> {
  StockQuoteSnapshot? get firstOrNull {
    for (final item in this) {
      return item;
    }
    return null;
  }
}
