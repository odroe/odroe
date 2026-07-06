# Odroe

Odroe is a set of platform-neutral design and application primitives for Dart.

The current package surface is `package:odroe/style.dart`: a set of style
primitives for declaring typed design vocabulary, theme bindings, reusable
appearances, style contracts, conditional cases, design validation, and resolved
style values before projecting them to any UI platform.

It is not a Flutter theme helper, CSS DSL, Material wrapper, Jaspr component
library, or code generator. Platform adapters can be built on top of these
primitives later.

## Style Primitives

Import the style primitives from one public entrypoint:

```dart
import 'package:odroe/style.dart';
```

A style system starts with vocabulary terms:

```dart
const actionFill = Term<Color>(Identifier('color.action.fill'));
const actionContent = Term<Color>(Identifier('color.action.content'));
const controlRadius = Term<Dimension>(Identifier('radius.control'));
```

Bindings assign concrete values to those terms:

```dart
final light = Binding(Identifier('light'), [
  actionFill(const Color(0xff0969da)),
  actionContent(const Color(0xffffffff)),
  controlRadius(8.px),
]);
```

Styles reference terms without resolving them immediately:

```dart
final button = Style<void>(
  id: Identifier('button'),
  root: Appearance(
    surface: Surface(
      fill: .term(actionFill),
      radius: .term(controlRadius),
    ),
    content: Content(color: .term(actionContent)),
  ),
);
```

Resolution selects a binding and produces platform-neutral values:

```dart
final resolved = button.resolve(binding: light);

print(resolved.appearance.surface?.fill?.toARGB32().toRadixString(16));
```

## Design Manifests

Use `Design` when a package wants to validate a complete style system:

```dart
final design = Design(
  vocabulary: terms,
  bindings: [light, dark],
  styles: [button],
  policies: const [],
);

final diagnostics = design.validate();
```

Validation reports structured diagnostics for invalid identifiers, missing
binding values, unknown terms, incompatible term or axis values, contract
violations, and custom policy findings.

## Examples

Run the getting-started example:

```sh
dart run example/style_primitives.dart
```

The example demonstrates:

- a typed vocabulary tree;
- light and dark bindings;
- a button style with parts, states, axes, and cases;
- design validation;
- resolving a style to platform-neutral output values.

## Platform Boundary

The style primitives intentionally avoid platform output. They do not contain:

- CSS selectors or DOM nodes;
- Flutter widgets, `BuildContext`, `TextStyle`, `BoxDecoration`, or
  `ThemeData`;
- Material or Jaspr APIs;
- required macros, annotations, generators, or CLI projection.

Future CSS, Flutter, Material, Jaspr, or generator packages should consume these
primitives rather than changing their platform-neutral boundary.
