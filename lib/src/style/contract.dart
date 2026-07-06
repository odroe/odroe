import 'axis.dart';
import 'state.dart';

/// The optional styleable shape for a [Style].
///
/// A contract describes which semantic parts, axes, and states a styleable
/// object exposes. It has no identifier of its own because the owning `Style`
/// is the named resource.
///
/// ```dart
/// enum ButtonPart { icon, label }
/// enum ButtonTone { primary, danger }
///
/// const tone = Axis<ButtonTone>(
///   id: Identifier('button.tone'),
///   defaultValue: ButtonTone.primary,
/// );
///
/// final contract = Contract<ButtonPart>(
///   parts: {ButtonPart.icon, ButtonPart.label},
///   axes: [tone],
///   states: {state.hovered, state.disabled},
/// );
/// ```
final class Contract<P> {
  /// Creates a contract from optional styleable members.
  ///
  /// The collections are copied into immutable containers so later mutation of
  /// the source collections cannot change the contract.
  Contract({
    Iterable<P> parts = const [],
    Iterable<Axis<Object?>> axes = const [],
    Iterable<State> states = const [],
  }) : parts = Set.unmodifiable(parts),
       axes = List.unmodifiable(axes),
       states = Set.unmodifiable(states);

  /// The semantic parts a style can target.
  ///
  /// Parts are optional appearance targets keyed by the style's part type.
  final Set<P> parts;

  /// The variant axes accepted by styles using this contract.
  final List<Axis<Object?>> axes;

  /// The semantic states accepted by styles using this contract.
  final Set<State> states;

  /// Whether [part] is declared by this contract.
  bool allowsPart(P part) {
    return parts.contains(part);
  }

  /// Whether [axis] is declared by this contract.
  bool allowsAxis(Axis<Object?> axis) {
    return axes.any((declared) => declared.id == axis.id);
  }

  /// Whether [state] is declared by this contract.
  bool allowsState(State state) {
    return states.any((declared) => declared.id == state.id);
  }
}
