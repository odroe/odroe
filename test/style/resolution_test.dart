import 'package:odroe/style.dart';
import 'package:test/test.dart';

import '_utils.dart';

enum ButtonPart { icon, label }

enum ButtonSize { sm, md }

enum ButtonTone { primary, danger }

void main() {
  test('resolves term-backed properties through the selected binding', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    const radius = Term<Dimension>(Identifier('radius.control'));
    final binding = Binding(Identifier('light'), [
      fill(const Color(0xff006adc)),
      radius(8.px),
    ]);
    final style = Style<void>(
      id: Identifier('button'),
      root: const Appearance(
        surface: Surface(fill: .term(fill), radius: .term(radius)),
      ),
    );

    final resolution = style.resolve(binding: binding);

    expect(resolution.isValid, isTrue);
    expect(resolution.appearance.surface?.fill, const Color(0xff006adc));
    expect(resolution.appearance.surface?.radius, 8.px);
  });

  test('merges root part matching cases and instance override in order', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    const hoverFill = Term<Color>(Identifier('color.action.fillHover'));
    const dangerFill = Term<Color>(Identifier('color.danger.fill'));
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    final binding = Binding(Identifier('light'), [
      fill(const Color(0xff006adc)),
      hoverFill(const Color(0xff0055aa)),
      dangerFill(const Color(0xffc62828)),
    ]);
    final style = Style<ButtonPart>(
      id: Identifier('button'),
      root: const Appearance(
        surface: Surface(fill: .term(fill), radius: .literal(Dimension.px(8))),
      ),
      parts: const {
        ButtonPart.icon: Appearance(
          surface: Surface(radius: .literal(Dimension.px(4))),
        ),
      },
      cases: [
        .when(
          state.hovered,
          const Appearance(surface: Surface(fill: .term(hoverFill))),
        ),
        .when(
          tone(.danger),
          const Appearance(surface: Surface(fill: .term(dangerFill))),
        ),
      ],
    );

    final resolution = style.resolve(
      binding: binding,
      part: ButtonPart.icon,
      states: [state.hovered],
      axisValues: [tone(.danger)],
      instanceOverride: const Appearance(
        surface: Surface(fill: .literal(Color(0xff111111))),
      ),
    );

    expect(resolution.diagnostics, isEmpty);
    expect(resolution.appearance.surface?.fill, const Color(0xff111111));
    expect(resolution.appearance.surface?.radius, 4.px);
  });

  test('applies matching cases in declaration order', () {
    final binding = Binding(Identifier('light'), const []);
    final style = Style<void>(
      id: Identifier('button'),
      root: const Appearance(content: Content(opacity: .literal(1))),
      cases: [
        .when(
          state.hovered,
          const Appearance(content: Content(opacity: .literal(0.8))),
        ),
        .when(
          state.hovered,
          const Appearance(content: Content(opacity: .literal(0.6))),
        ),
      ],
    );

    final resolution = style.resolve(binding: binding, states: [state.hovered]);

    expect(resolution.diagnostics, isEmpty);
    expect(resolution.appearance.content?.opacity, 0.6);
  });

  test('matches compound all any and not conditions', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    const size = Axis<ButtonSize>(
      id: Identifier('button.size'),
      defaultValue: ButtonSize.md,
    );
    final binding = Binding(Identifier('light'), const []);
    final style = Style<void>(
      id: Identifier('button'),
      root: const Appearance(content: Content(opacity: .literal(1))),
      cases: [
        .all([
          tone(.danger),
          size(.sm),
        ], const Appearance(content: Content(opacity: .literal(0.7)))),
        .any([
          state.pressed,
          state.focusVisible,
        ], const Appearance(content: Content(opacity: .literal(0.6)))),
        .when(
          Condition.not(state.disabled),
          const Appearance(content: Content(opacity: .literal(0.5))),
        ),
      ],
    );

    final resolution = style.resolve(
      binding: binding,
      states: [state.focusVisible],
      axisValues: [tone(.danger), size(.sm)],
    );

    expect(resolution.diagnostics, isEmpty);
    expect(resolution.appearance.content?.opacity, 0.5);
  });

  test('reports unresolved terms in the final merged appearance', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    final binding = Binding(Identifier('light'), const []);
    final style = Style<void>(
      id: Identifier('button'),
      root: const Appearance(surface: Surface(fill: .term(fill))),
    );

    final resolution = style.resolve(binding: binding);

    expect(
      resolution.diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.resolutionUnresolvedTerm,
        targetKind: 'term',
        targetName: 'color.action.fill',
      ),
    );
    expect(resolution.appearance.surface?.fill, isNull);
  });

  test('does not resolve overwritten term references', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    final binding = Binding(Identifier('light'), const []);
    final style = Style<void>(
      id: Identifier('button'),
      root: const Appearance(surface: Surface(fill: .term(fill))),
    );

    final resolution = style.resolve(
      binding: binding,
      instanceOverride: const Appearance(
        surface: Surface(fill: .literal(Color(0xff111111))),
      ),
    );

    expect(resolution.diagnostics, isEmpty);
    expect(resolution.appearance.surface?.fill, const Color(0xff111111));
  });

  test('reports incompatible binding values while resolving terms', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    const wrongFill = Term<Dimension>(Identifier('color.action.fill'));
    final binding = Binding(Identifier('light'), [wrongFill(8.px)]);
    final style = Style<void>(
      id: Identifier('button'),
      root: const Appearance(surface: Surface(fill: .term(fill))),
    );

    final resolution = style.resolve(binding: binding);

    expect(
      resolution.diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.resolutionInvalidTermValueType,
        targetKind: 'term',
        targetName: 'color.action.fill',
      ),
    );
  });

  test('reports contract violations while matching conditions and parts', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    const size = Axis<ButtonSize>(
      id: Identifier('button.size'),
      defaultValue: ButtonSize.md,
    );
    final binding = Binding(Identifier('light'), const []);
    final style = Style<ButtonPart>(
      id: Identifier('button'),
      contract: Contract<ButtonPart>(
        parts: {ButtonPart.icon},
        axes: [tone],
        states: {state.hovered},
      ),
      root: const Appearance(),
      cases: [
        .when(size(.sm), const Appearance()),
        .when(state.disabled, const Appearance()),
      ],
    );

    final resolution = style.resolve(
      binding: binding,
      part: ButtonPart.label,
      states: [state.disabled],
      axisValues: [size(.sm)],
    );

    expect(
      resolution.diagnostics,
      containsDiagnostic(code: DiagnosticCodes.styleUnknownPart),
    );
    expect(
      resolution.diagnostics,
      containsDiagnostic(code: DiagnosticCodes.styleUnknownAxis),
    );
    expect(
      resolution.diagnostics,
      containsDiagnostic(code: DiagnosticCodes.styleUnknownState),
    );
  });

  test('reports unsupported condition types', () {
    final binding = Binding(Identifier('light'), const []);
    final style = Style<void>(
      id: Identifier('button'),
      root: const Appearance(),
      cases: [.when(const _UnsupportedCondition(), const Appearance())],
    );

    final resolution = style.resolve(binding: binding);

    expect(
      resolution.diagnostics,
      containsDiagnostic(code: DiagnosticCodes.resolutionUnsupportedCondition),
    );
  });
}

final class _UnsupportedCondition extends Condition {
  const _UnsupportedCondition();
}
