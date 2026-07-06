import 'package:odroe/style.dart';
import 'package:test/test.dart';

import '_utils.dart';

enum ButtonPart { icon, label }

enum ButtonTone { primary, danger }

void main() {
  test('stores manifest collections in immutable lists', () {
    const t = _AppTerms();
    final bindings = [
      Binding(Identifier('light'), [
        t.color.action.fill(const Color(0xff006adc)),
        t.color.action.content(const Color(0xffffffff)),
        t.radius.control(8.px),
      ]),
    ];
    final styles = [
      Style<void>(id: Identifier('button'), root: const Appearance()),
    ];

    final design = Design(vocabulary: t, bindings: bindings, styles: styles);
    bindings.clear();
    styles.clear();

    expect(design.vocabulary, same(t));
    expect(design.vocabulary.color.action.fill.id.value, 'color.action.fill');
    expect(design.terms, [
      t.color.action.fill,
      t.color.action.content,
      t.radius.control,
    ]);
    expect(design.bindings, hasLength(1));
    expect(design.styles, hasLength(1));
    expect(() => design.terms.clear(), throwsUnsupportedError);
    expect(() => design.bindings.clear(), throwsUnsupportedError);
  });

  test('reports duplicate identifiers across manifest namespaces', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    const sameFill = Term<Color>(Identifier('color.action.fill'));
    const caseFill = Term<Color>(Identifier('Color.Action.Fill'));

    final diagnostics = Design(
      vocabulary: const _TermListVocabulary(<Term>[fill, sameFill, caseFill]),
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
    const t = _AppTerms();

    final diagnostics = Design(
      vocabulary: t,
      bindings: [
        Binding(Identifier('light'), [
          t.color.action.fill(const Color(0xff006adc)),
        ]),
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
      vocabulary: const _TermListVocabulary(<Term>[fill]),
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
      vocabulary: const _TermListVocabulary(),
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
      vocabulary: const _TermListVocabulary(),
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
      vocabulary: const _TermListVocabulary(),
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
      vocabulary: const _TermListVocabulary(),
      policies: const [_AlwaysReportPolicy()],
    ).validate();

    expect(diagnostics, containsDiagnosticCode(_AlwaysReportPolicy.codeValue));
  });
}

final class _AppTerms implements Vocabulary {
  const _AppTerms();

  _ColorTerms get color => const _ColorTerms();

  _RadiusTerms get radius => const _RadiusTerms();

  @override
  Iterable<Term> get terms => [
    color.action.fill,
    color.action.content,
    radius.control,
  ];
}

final class _ColorTerms {
  const _ColorTerms();

  _ActionColorTerms get action => const _ActionColorTerms();
}

final class _ActionColorTerms {
  const _ActionColorTerms();

  Term<Color> get fill => const Term(Identifier('color.action.fill'));

  Term<Color> get content => const Term(Identifier('color.action.content'));
}

final class _RadiusTerms {
  const _RadiusTerms();

  Term<Dimension> get control => const Term(Identifier('radius.control'));
}

final class _TermListVocabulary implements Vocabulary {
  const _TermListVocabulary([this.terms = const []]);

  @override
  final List<Term> terms;
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
