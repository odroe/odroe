/// A condition that controls whether a case applies.
///
/// Conditions are the single conditional styling model in Odroe. Axis values,
/// states, and compound logic all flow through this type instead of separate
/// `variants`, `states`, `rules`, or `compoundVariants` APIs.
abstract base class Condition {
  /// Creates a condition.
  const Condition();

  /// Creates a condition that matches when every [condition] matches.
  factory Condition.all(Iterable<Condition> conditions) {
    return AllCondition(conditions);
  }

  /// Creates a condition that matches when any [condition] matches.
  factory Condition.any(Iterable<Condition> conditions) {
    return AnyCondition(conditions);
  }

  /// Creates a condition that matches when [condition] does not match.
  const factory Condition.not(Condition condition) = NotCondition;
}

/// A condition that requires every child condition to match.
final class AllCondition extends Condition {
  /// Creates a compound condition from [conditions].
  AllCondition(Iterable<Condition> conditions)
    : conditions = List.unmodifiable(conditions);

  /// The conditions that must all match.
  final List<Condition> conditions;
}

/// A condition that requires at least one child condition to match.
final class AnyCondition extends Condition {
  /// Creates a compound condition from [conditions].
  AnyCondition(Iterable<Condition> conditions)
    : conditions = List.unmodifiable(conditions);

  /// The conditions where any one match is sufficient.
  final List<Condition> conditions;
}

/// A condition that negates another condition.
final class NotCondition extends Condition {
  /// Creates a negated condition.
  const NotCondition(this.condition);

  /// The condition whose match result is negated.
  final Condition condition;
}
