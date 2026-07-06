/// Platform-neutral style declarations for Odroe.
///
/// This library models style systems before they are projected to a UI
/// framework or output format. It intentionally contains no Flutter widgets,
/// CSS selectors, DOM nodes, Material types, or Jaspr APIs.
///
/// A style system starts with named terms, then assigns concrete values through
/// bindings:
///
/// ```dart
/// const actionFill = Term<String>(Identifier('color.action.fill'));
/// const actionContent = Term<String>(Identifier('color.action.content'));
///
/// final light = Binding(Identifier('light'), [
///   actionFill('#006adc'),
///   actionContent('#ffffff'),
/// ]);
/// ```
///
/// Values are not resolved when declarations are created. Later style APIs will
/// choose a binding, merge appearances, and produce platform-neutral resolved
/// values that other packages can adapt for Flutter, CSS, or other targets.
library;

export 'src/style/appearance.dart';
export 'src/style/binding.dart';
export 'src/style/diagnostic.dart';
export 'src/style/identifier.dart';
