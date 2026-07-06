import 'appearance.dart';
import 'case.dart';
import 'contract.dart';
import 'identifier.dart';

/// A named platform-neutral style declaration.
///
/// A style is not a widget, DOM component, or Material component. It names a
/// reusable visual declaration with a root [Appearance], optional semantic
/// parts, and conditional [Case] overrides. A [contract] can describe the shape
/// that later validators should enforce, but a style can also be declared
/// without one.
///
/// ```dart
/// enum ButtonPart { icon, label }
///
/// final button = Style<ButtonPart>(
///   id: Identifier('button'),
///   root: Appearance(),
///   parts: {
///     ButtonPart.icon: Appearance(),
///     ButtonPart.label: Appearance(),
///   },
///   cases: [
///     .when(state.hovered, Appearance()),
///   ],
/// );
/// ```
final class Style<P> {
  /// Creates a style declaration.
  ///
  /// [parts] and [cases] are copied into immutable containers so source
  /// collection mutation cannot change the declaration after construction.
  Style({
    required this.id,
    required this.root,
    this.contract,
    Map<P, Appearance> parts = const {},
    Iterable<Case> cases = const [],
  }) : parts = Map.unmodifiable(parts),
       cases = List.unmodifiable(cases);

  /// The stable style identifier.
  final Identifier id;

  /// The optional contract describing parts, axes, and states for this style.
  final Contract<P>? contract;

  /// The root appearance for this style.
  final Appearance root;

  /// Optional semantic part appearances keyed by the style's part type.
  final Map<P, Appearance> parts;

  /// Conditional appearance overrides.
  final List<Case> cases;
}
