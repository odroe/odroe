import 'condition.dart';
import 'identifier.dart';

/// A semantic visual state exposed to style declarations.
///
/// States describe platform-neutral interaction or data states such as hover,
/// pressed, disabled, selected, or error. Platform pseudo selectors and widget
/// lifecycle details are adapter concerns, not core states.
final class State extends Condition {
  /// Creates a state with a stable [id].
  const State(this.id);

  /// The authoring name for this state.
  final Identifier id;

  @override
  bool operator ==(Object other) {
    return other is State && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// The built-in style state namespace.
///
/// Use this value as the public entry point for core semantic states:
///
/// ```dart
/// final hoveredCase = Case.when(state.hovered, Appearance());
/// ```
const state = States._();

/// Built-in platform-neutral visual states.
///
/// The namespace keeps common states discoverable without exporting global
/// constants for each individual state.
final class States {
  const States._();

  /// Pointer hover state.
  State get hovered => const State(Identifier('state.hovered'));

  /// Active press state.
  State get pressed => const State(Identifier('state.pressed'));

  /// Input focus state.
  State get focused => const State(Identifier('state.focused'));

  /// Focus state that should display a visible focus affordance.
  State get focusVisible => const State(Identifier('state.focusVisible'));

  /// Disabled state.
  State get disabled => const State(Identifier('state.disabled'));

  /// Selected state.
  State get selected => const State(Identifier('state.selected'));

  /// Checked state.
  State get checked => const State(Identifier('state.checked'));

  /// Expanded state.
  State get expanded => const State(Identifier('state.expanded'));

  /// Loading or pending state.
  State get loading => const State(Identifier('state.loading'));

  /// Error state.
  State get error => const State(Identifier('state.error'));
}
