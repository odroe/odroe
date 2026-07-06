import 'package:odroe/style.dart';
import 'package:test/test.dart';

import '../../example/style_primitives.dart' as example;

void main() {
  test('validates the style primitives example design', () {
    final diagnostics = example.design.validate();

    expect(diagnostics.map((diagnostic) => diagnostic.toString()), isEmpty);
    expect(example.design.bindings.map((binding) => binding.id.value), [
      'light',
      'dark',
    ]);
    expect(example.design.styles.map((style) => style.id.value), [
      'button',
      'card',
      'textField',
    ]);
  });

  test('resolves button parts states and axes from the example', () {
    final resolution = example.button.resolve(
      binding: example.dark,
      part: example.ButtonPart.icon,
      states: [state.hovered, state.focusVisible],
      axisValues: [example.buttonTone(.danger), example.buttonSize(.sm)],
    );

    expect(resolution.diagnostics, isEmpty);
    expect(resolution.appearance.surface?.fill, const Color(0xffff7b72));
    expect(resolution.appearance.surface?.stroke, const Color(0xff1f6feb));
    expect(resolution.appearance.surface?.radius, 8.px);
    expect(resolution.appearance.content?.color, const Color(0xff0d1117));
    expect(
      resolution.appearance.content?.icon,
      const Identifier('icon.buttonLeading'),
    );
    expect(
      resolution.appearance.content?.text,
      const Identifier('text.buttonLabelSm'),
    );
    expect(resolution.appearance.metrics?.width, 16.px);
    expect(resolution.appearance.metrics?.minHeight, 32.px);
    expect(resolution.appearance.metrics?.padding?.left, 12.px);
    expect(resolution.appearance.metrics?.padding?.top, 6.px);
  });

  test('resolves card surface roles across light and dark bindings', () {
    final lightRaised = example.card.resolve(binding: example.light);
    final darkOverlay = example.card.resolve(
      binding: example.dark,
      part: example.CardPart.header,
      axisValues: [example.surfaceRole(.overlay)],
    );

    expect(lightRaised.diagnostics, isEmpty);
    expect(darkOverlay.diagnostics, isEmpty);
    expect(lightRaised.appearance.surface?.fill, const Color(0xfff8f8f8));
    expect(lightRaised.appearance.surface?.elevation, 2.px);
    expect(darkOverlay.appearance.surface?.fill, const Color(0xff21262d));
    expect(darkOverlay.appearance.surface?.stroke, const Color(0xff8b949e));
    expect(darkOverlay.appearance.surface?.elevation, 8.px);
    expect(
      darkOverlay.appearance.content?.text,
      const Identifier('text.cardTitle'),
    );
  });

  test('models text field gaps with semantic parts and states', () {
    final placeholder = example.textField.resolve(
      binding: example.light,
      part: example.TextFieldPart.placeholder,
    );
    final focusedError = example.textField.resolve(
      binding: example.light,
      part: example.TextFieldPart.error,
      states: [state.focused, state.error],
    );
    final disabledInput = example.textField.resolve(
      binding: example.dark,
      part: example.TextFieldPart.input,
      states: [state.disabled],
    );

    expect(placeholder.diagnostics, isEmpty);
    expect(focusedError.diagnostics, isEmpty);
    expect(disabledInput.diagnostics, isEmpty);
    expect(placeholder.appearance.content?.color, const Color(0xff6e7781));
    expect(
      placeholder.appearance.content?.text,
      const Identifier('text.fieldInput'),
    );
    expect(focusedError.appearance.surface?.stroke, const Color(0xffcf222e));
    expect(
      focusedError.appearance.content?.icon,
      const Identifier('icon.fieldError'),
    );
    expect(
      focusedError.appearance.content?.text,
      const Identifier('text.fieldError'),
    );
    expect(disabledInput.appearance.surface?.fill, const Color(0xff161b22));
    expect(disabledInput.appearance.content?.opacity, 0.52);
  });
}
