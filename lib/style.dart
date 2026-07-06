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
/// const actionFill = Term<Color>(Identifier('color.action.fill'));
/// const actionContent = Term<Color>(Identifier('color.action.content'));
///
/// final light = Binding(Identifier('light'), [
///   actionFill(Color(0xff006adc)),
///   actionContent(Color(0xffffffff)),
/// ]);
/// ```
///
/// Values are not resolved when declarations are created. Later style APIs will
/// choose a binding, merge appearances, and produce platform-neutral resolved
/// values that other packages can adapt for Flutter, CSS, or other targets.
library;

export 'src/style/appearance.dart';
export 'src/style/axis.dart';
export 'src/style/binding.dart';
export 'src/style/case.dart';
export 'src/style/color.dart';
export 'src/style/condition.dart';
export 'src/style/contract.dart';
export 'src/style/diagnostic.dart';
export 'src/style/dimension.dart';
export 'src/style/identifier.dart';
export 'src/style/state.dart';
export 'src/style/style_declaration.dart';
