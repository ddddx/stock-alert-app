class RuleEvaluationState {
  const RuleEvaluationState({
    required this.ruleId,
    this.active = false,
    this.lastStepIndex,
    this.lastTriggeredAt,
  });

  final String ruleId;
  final bool active;
  final int? lastStepIndex;
  final DateTime? lastTriggeredAt;

  RuleEvaluationState copyWith({
    bool? active,
    int? lastStepIndex,
    DateTime? lastTriggeredAt,
  }) {
    return RuleEvaluationState(
      ruleId: ruleId,
      active: active ?? this.active,
      lastStepIndex: lastStepIndex ?? this.lastStepIndex,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
    );
  }
}
