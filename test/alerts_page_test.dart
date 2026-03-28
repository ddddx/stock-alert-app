import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_alert_app/data/models/alert_rule.dart';
import 'package:stock_alert_app/data/models/stock_identity.dart';
import 'package:stock_alert_app/data/repositories/alert_repository.dart';
import 'package:stock_alert_app/data/repositories/watchlist_repository.dart';
import 'package:stock_alert_app/features/alerts/presentation/pages/alerts_page.dart';

import 'support/test_app.dart';

void main() {
  testWidgets(
      'alerts page can add a generic global rule without watchlist stocks', (
    tester,
  ) async {
    final alertRepository = _FakeAlertRepository();
    final watchlistRepository = _FakeWatchlistRepository();

    await tester.pumpWidget(
      _buildApp(
        AlertsPage(
          repository: alertRepository,
          watchlistRepository: watchlistRepository,
          quotes: const [],
        ),
      ),
    );

    await tester.tap(find.text('添加规则'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(alertRepository.rules, hasLength(1));
    expect(alertRepository.rules.single.applyToAllWatchlist, isTrue);
    expect(alertRepository.rules.single.targetStocks, isEmpty);
    expect(find.text('目标范围：全部自选股'), findsOneWidget);
  });

  testWidgets('alerts page updates selected target stocks while editing a rule',
      (
    tester,
  ) async {
    final alertRepository = _FakeAlertRepository(
      rules: [
        AlertRule.shortWindowMove(
          id: 'rule-1',
          stockCode: '600519',
          stockName: 'Alpha',
          market: 'SH',
          targetStocks: const [
            StockIdentity(code: '600519', name: 'Alpha', market: 'SH'),
          ],
          moveThresholdPercent: 1,
          lookbackMinutes: 5,
          moveDirection: MoveDirection.either,
          enabled: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final watchlistRepository = _FakeWatchlistRepository(
      items: const [
        StockIdentity(code: '600519', name: 'Alpha', market: 'SH'),
        StockIdentity(code: '000001', name: 'Beta', market: 'SZ'),
      ],
    );

    await tester.pumpWidget(
      _buildApp(
        AlertsPage(
          repository: alertRepository,
          watchlistRepository: watchlistRepository,
          quotes: const [],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('edit-rule-rule-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beta (000001)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha (600519)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      alertRepository.rules.single.resolvedTargetStocks
          .map((item) => item.code),
      ['000001'],
    );
    expect(find.text('目标范围：Beta (000001)'), findsOneWidget);
  });

  testWidgets('alerts page deletes an existing rule', (tester) async {
    final alertRepository = _FakeAlertRepository(
      rules: [
        AlertRule.shortWindowMove(
          id: 'rule-1',
          stockCode: '600519',
          stockName: 'Alpha',
          market: 'SH',
          moveThresholdPercent: 1,
          lookbackMinutes: 5,
          moveDirection: MoveDirection.either,
          enabled: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
    );

    await tester.pumpWidget(
      _buildApp(
        AlertsPage(
          repository: alertRepository,
          watchlistRepository: _FakeWatchlistRepository(),
          quotes: const [],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('delete-rule-rule-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(alertRepository.rules, isEmpty);
    expect(find.text('还没有提醒规则，添加一条后即可开始监控。'), findsOneWidget);
  });
}

MaterialApp _buildApp(Widget child) {
  return buildTestApp(child);
}

class _FakeAlertRepository implements AlertRepository {
  _FakeAlertRepository({List<AlertRule>? rules}) : rules = [...?rules];

  final List<AlertRule> rules;

  @override
  Future<void> add(AlertRule rule) async {
    rules.insert(0, rule);
  }

  @override
  Future<void> delete(String id) async {
    rules.removeWhere((item) => item.id == id);
  }

  @override
  List<AlertRule> getAll() => List.unmodifiable(rules);

  @override
  List<AlertRule> getEnabledRules() {
    return rules.where((item) => item.enabled).toList(growable: false);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> toggle(String id, bool enabled) async {
    final index = rules.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    rules[index] = rules[index].copyWith(enabled: enabled);
  }

  @override
  Future<void> update(AlertRule rule) async {
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index == -1) {
      return;
    }
    rules[index] = rule;
  }

  @override
  Future<void> replaceAll(List<AlertRule> nextRules) async {
    rules
      ..clear()
      ..addAll(nextRules);
  }
}

class _FakeWatchlistRepository implements WatchlistRepository {
  _FakeWatchlistRepository({List<StockIdentity>? items}) : _items = [...?items];

  final List<StockIdentity> _items;

  @override
  Future<bool> add(StockIdentity stock) async {
    _items.add(stock);
    return true;
  }

  @override
  bool contains(String code) => _items.any((item) => item.code == code);

  @override
  List<StockIdentity> getAll() => List.unmodifiable(_items);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> remove(String code) async {
    _items.removeWhere((item) => item.code == code);
  }

  @override
  Future<void> replaceAll(List<StockIdentity> stocks) async {
    _items
      ..clear()
      ..addAll(stocks);
  }
}
