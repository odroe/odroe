import 'package:odroe/style.dart';
import 'package:test/test.dart';

import '_utils.dart';

enum ButtonPart { icon, label }

enum ButtonTone { primary, danger }

void main() {
  test('stores manifest collections in immutable lists', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    final vocabulary = <Term<Object?>>[fill];
    final terms = _TestVocabulary(vocabulary);
    final bindings = [
      Binding(Identifier('light'), [fill(const Color(0xff006adc))]),
    ];
    final styles = [
      Style<void>(id: Identifier('button'), root: const Appearance()),
    ];

    final design = Design(terms: terms, bindings: bindings, styles: styles);
    vocabulary.clear();
    bindings.clear();
    styles.clear();

    expect(design.terms, same(terms));
    expect(design.vocabulary, [fill]);
    expect(design.bindings, hasLength(1));
    expect(design.styles, hasLength(1));
    expect(() => design.vocabulary.clear(), throwsUnsupportedError);
    expect(() => design.bindings.clear(), throwsUnsupportedError);
  });

  test('reports duplicate identifiers across manifest namespaces', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    const sameFill = Term<Color>(Identifier('color.action.fill'));
    const caseFill = Term<Color>(Identifier('Color.Action.Fill'));

    final diagnostics = Design(
      terms: const _TestVocabulary(<Term<Object?>>[fill, sameFill, caseFill]),
      bindings: [
        Binding(Identifier('light'), [fill(const Color(0xff006adc))]),
        Binding(Identifier('light'), [fill(const Color(0xff006adc))]),
      ],
      styles: [
        Style<void>(id: Identifier('button'), root: const Appearance()),
        Style<void>(id: Identifier('button'), root: const Appearance()),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.identifierDuplicate),
    );
    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.identifierDuplicateIgnoringCase),
    );
  });

  test('reports missing vocabulary terms in bindings', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    const content = Term<Color>(Identifier('color.action.content'));

    final diagnostics = Design(
      terms: const _TestVocabulary(<Term<Object?>>[fill, content]),
      bindings: [
        Binding(Identifier('light'), [fill(const Color(0xff006adc))]),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.designMissingBindingValue),
    );
  });

  test('keeps binding-level duplicate assignment diagnostics', () {
    const fill = Term<Color>(Identifier('color.action.fill'));

    final diagnostics = Design(
      terms: const _TestVocabulary(<Term<Object?>>[fill]),
      bindings: [
        Binding(Identifier('light'), [
          fill(const Color(0xff006adc)),
          fill(const Color(0xff0055aa)),
        ]),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.bindingDuplicateAssignment),
    );
  });

  test('reports style members not declared by the contract', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    const density = Axis<int>(
      id: Identifier('button.density'),
      defaultValue: 0,
    );
    final contract = Contract<ButtonPart>(
      parts: {ButtonPart.icon},
      axes: [tone],
      states: {state.hovered},
    );

    final diagnostics = Design(
      terms: const _TestVocabulary(),
      styles: [
        Style<ButtonPart>(
          id: Identifier('button'),
          contract: contract,
          root: const Appearance(),
          parts: const {ButtonPart.label: Appearance()},
          cases: [
            .when(density(1), const Appearance()),
            .when(state.disabled, const Appearance()),
          ],
        ),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.styleUnknownPart),
    );
    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.styleUnknownAxis),
    );
    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.styleUnknownState),
    );
  });

  test('validates condition identifiers without requiring a contract', () {
    const invalidAxis = Axis<int>(
      id: Identifier('button-axis'),
      defaultValue: 0,
    );

    final diagnostics = Design(
      terms: const _TestVocabulary(),
      styles: [
        Style<void>(
          id: Identifier('button'),
          root: const Appearance(),
          cases: [
            .when(invalidAxis(1), const Appearance()),
            .when(
              const State(Identifier('state..hovered')),
              const Appearance(),
            ),
          ],
        ),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.identifierInvalidSegment),
    );
    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.identifierEmptySegment),
    );
  });

  test('reports duplicate contract axis and state identifiers', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    const sameTone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.danger,
    );
    const hovered = State(Identifier('state.hovered'));

    final diagnostics = Design(
      terms: const _TestVocabulary(),
      styles: [
        Style<ButtonPart>(
          id: Identifier('button'),
          contract: Contract<ButtonPart>(
            axes: [tone, sameTone],
            states: {hovered, state.hovered},
          ),
          root: const Appearance(),
        ),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnosticCode(DiagnosticCodes.identifierDuplicate),
    );
  });

  test('runs custom policy objects', () {
    final diagnostics = Design(
      terms: const _TestVocabulary(),
      policies: const [_AlwaysReportPolicy()],
    ).validate();

    expect(diagnostics, containsDiagnosticCode(_AlwaysReportPolicy.codeValue));
  });
}

final class _TestVocabulary implements Vocabulary {
  const _TestVocabulary([this.terms = const []]);

  @override
  final List<Term<Object?>> terms;
}

final class _AlwaysReportPolicy implements Policy {
  const _AlwaysReportPolicy();

  static const codeValue = 'design.always_report';

  @override
  String get code => codeValue;

  @override
  void evaluate(PolicyContext context) {
    context.report(
      const Diagnostic(
        code: codeValue,
        message: 'Policy reported a diagnostic.',
      ),
    );
  }
}
