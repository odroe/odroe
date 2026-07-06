import 'condition.dart';
import 'identifier.dart';
import 'value_contract.dart';

/// A typed style axis that can produce conditions for one axis value.
///
/// Axes model authored variants such as tone, size, density, or emphasis. An
/// axis is not a resolved value; it describes one input dimension that a later
/// style resolver can match against.
///
/// Calling an axis creates an [AxisCondition]:
///
/// ```dart
/// enum ButtonTone { primary, danger }
///
/// const tone = Axis<ButtonTone>(
///   id: Identifier('button.tone'),
///   defaultValue: ButtonTone.primary,
/// );
///
/// final danger = tone(.danger);
/// ```
final class Axis<T> implements ValueContract<T> {
  /// Creates a style axis with a stable [id] and [defaultValue].
  const Axis({required this.id, required this.defaultValue});

  /// The authoring name used for validation, diagnostics, and future tooling.
  @override
  final Identifier id;

  /// The value used when no condition provides a value for this axis.
  final T defaultValue;

  /// The runtime type represented by this axis.
  ///
  /// Validators use this after declarations have been widened to
  /// `Axis<Object?>` and need to compare a condition axis against a contract
  /// axis.
  @override
  Type get valueType => T;

  /// Whether [value] can be used as a value for this axis.
  ///
  /// This mirrors the static contract enforced by [call]. It lets design-level
  /// validation reject conditions built from a different axis object that reuses
  /// the same identifier with an incompatible type argument.
  @override
  bool acceptsValue(Object? value) {
    return value is T;
  }

  /// Whether [contract] names this same typed style axis.
  ///
  /// Two value contracts are compatible only when both the identifier and value
  /// type match. This lets validators distinguish an undeclared axis from an
  /// axis that reuses the same identifier with a different type argument.
  @override
  bool acceptsContract(ValueContract<Object?> contract) {
    return contract.id == id && contract.valueType == valueType;
  }

  /// Creates a condition that matches this axis at [value].
  AxisCondition<T> call(T value) {
    return AxisCondition<T>(this, value);
  }

  @override
  bool operator ==(Object other) {
    return other is Axis<Object?> &&
        other.id == id &&
        other.defaultValue == defaultValue;
  }

  @override
  int get hashCode => Object.hash(id, defaultValue);
}

/// A condition produced by an [Axis] and one typed axis value.
final class AxisCondition<T> extends Condition {
  /// Creates a condition that matches [axis] at [value].
  const AxisCondition(this.axis, this.value);

  /// The axis being matched.
  final Axis<T> axis;

  /// The axis value being matched.
  final T value;
}
