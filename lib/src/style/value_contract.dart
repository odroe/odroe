import 'identifier.dart';

/// A typed declaration that can validate values after generic type widening.
///
/// Core style declarations are authored with static Dart types, but validators
/// often receive them through wider surfaces such as `Term`, `Axis<Object?>`, or
/// `Assignment<Object?>`. A value contract preserves the runtime pieces needed
/// to check those widened declarations without guessing from identifiers alone.
///
/// [Term] and [Axis] both implement this contract. A validator can first match
/// declarations by [id], then use [acceptsContract] and [acceptsValue] to reject
/// declarations that reuse an identifier with the wrong value type.
abstract interface class ValueContract<T> {
  /// The authoring name used for validation, diagnostics, and future tooling.
  Identifier get id;

  /// The runtime type represented by this declaration.
  Type get valueType;

  /// Whether [value] can be used with this declaration.
  bool acceptsValue(Object? value);

  /// Whether [contract] names this same typed declaration.
  ///
  /// Compatible contracts must have the same [id] and [valueType].
  bool acceptsContract(ValueContract<Object?> contract);
}
