class RuleEvaluationState {
  const RuleEvaluationState({
    required this.ruleId,
    this.active = false,
    this.lastStepIndex,
    this.lastTriggeredAt,
    this.stepAnchorPrice,
  });

  final String ruleId;
  final bool active;
  final int? lastStepIndex;
  final DateTime? lastTriggeredAt;
  final double? stepAnchorPrice;

  RuleEvaluationState copyWith({
    bool? active,
    int? lastStepIndex,
    DateTime? lastTriggeredAt,
    double? stepAnchorPrice,
  }) {
    return RuleEvaluationState(
      ruleId: ruleId,
      active: active ?? this.active,
      lastStepIndex: lastStepIndex ?? this.lastStepIndex,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
      stepAnchorPrice: stepAnchorPrice ?? this.stepAnchorPrice,
    );
  }
}
