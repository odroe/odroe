import 'appearance.dart';
import 'condition.dart';

/// A conditional appearance override.
///
/// A case pairs one [Condition] with the [Appearance] that should apply when
/// the condition matches. Cases deliberately replace separate variant, state,
/// rule, and compound-variant APIs with one data model.
///
/// Dart dot shorthand keeps case authoring compact in `List<Case>` contexts:
///
/// ```dart
/// final cases = <Case>[
///   .when(state.hovered, Appearance()),
///   .all([state.focused, state.error], Appearance()),
/// ];
/// ```
final class Case {
  /// Creates a case for [when] and [appearance].
  const Case(this.when, this.appearance);

  /// Creates a case that applies when [condition] matches.
  const factory Case.when(Condition condition, Appearance appearance) = Case;

  /// Creates a case that applies when every [condition] matches.
  factory Case.all(Iterable<Condition> conditions, Appearance appearance) {
    return Case(Condition.all(conditions), appearance);
  }

  /// Creates a case that applies when any [condition] matches.
  factory Case.any(Iterable<Condition> conditions, Appearance appearance) {
    return Case(Condition.any(conditions), appearance);
  }

  /// The condition that controls whether [appearance] applies.
  final Condition when;

  /// The appearance applied when [when] matches.
  final Appearance appearance;
}
