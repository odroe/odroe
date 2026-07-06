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

  test('reports duplicate vocabulary term identifiers', () {
    const fill = Term<Color>(Identifier('color.action.fill'));
    const sameFill = Term<Color>(Identifier('color.action.fill'));
    const caseFill = Term<Color>(Identifier('Color.Action.Fill'));

    final diagnostics = Design(
      vocabulary: const _TermListVocabulary(<Term>[fill, sameFill, caseFill]),
    ).validate();

    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.identifierDuplicate,
        targetKind: 'term',
        targetName: 'color.action.fill',
      ),
    );
    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.identifierDuplicateIgnoringCase,
        targetKind: 'term',
        targetName: 'Color.Action.Fill',
      ),
    );
  });

  test('reports duplicate binding identifiers', () {
    final diagnostics = Design(
      vocabulary: const _TermListVocabulary(),
      bindings: [
        Binding(Identifier('light'), const []),
        Binding(Identifier('light'), const []),
        Binding(Identifier('Light'), const []),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.identifierDuplicate,
        targetKind: 'binding',
        targetName: 'light',
      ),
    );
    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.identifierDuplicateIgnoringCase,
        targetKind: 'binding',
        targetName: 'Light',
      ),
    );
  });

  test('reports duplicate style identifiers', () {
    final diagnostics = Design(
      vocabulary: const _TermListVocabulary(),
      styles: [
        Style<void>(id: Identifier('button'), root: const Appearance()),
        Style<void>(id: Identifier('button'), root: const Appearance()),
        Style<void>(id: Identifier('Button'), root: const Appearance()),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.identifierDuplicate,
        targetKind: 'style',
        targetName: 'button',
      ),
    );
    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.identifierDuplicateIgnoringCase,
        targetKind: 'style',
        targetName: 'Button',
      ),
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
      containsDiagnostic(code: DiagnosticCodes.designMissingBindingValue),
    );
  });

  test('reports binding assignments outside the vocabulary', () {
    const t = _AppTerms();
    const brandFill = Term<Color>(Identifier('color.brand.fill'));

    final diagnostics = Design(
      vocabulary: t,
      bindings: [
        Binding(Identifier('light'), [
          t.color.action.fill(const Color(0xff006adc)),
          t.color.action.content(const Color(0xffffffff)),
          t.radius.control(8.px),
          brandFill(const Color(0xff123456)),
        ]),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.designUnknownBindingValue,
        targetKind: 'assignment',
        targetName: 'color.brand.fill',
      ),
    );
    expect(
      diagnostics,
      isNot(
        containsDiagnostic(code: DiagnosticCodes.designMissingBindingValue),
      ),
    );
  });

  test('reports binding assignments with incompatible value types', () {
    const t = _AppTerms();
    const wrongFill = Term<Dimension>(Identifier('color.action.fill'));

    final diagnostics = Design(
      vocabulary: t,
      bindings: [
        Binding(Identifier('light'), [
          wrongFill(8.px),
          t.color.action.content(const Color(0xffffffff)),
          t.radius.control(8.px),
        ]),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.designInvalidBindingValueType,
        targetKind: 'assignment',
        targetName: 'color.action.fill',
      ),
    );
    expect(
      diagnostics,
      containsDiagnostic(code: DiagnosticCodes.designMissingBindingValue),
    );
  });

  test('reports style term references outside the vocabulary', () {
    const t = _AppTerms();
    const brandFill = Term<Color>(Identifier('color.brand.fill'));
    const brandRadius = Term<Dimension>(Identifier('radius.brand'));

    final diagnostics = Design(
      vocabulary: t,
      styles: [
        Style<ButtonPart>(
          id: Identifier('button'),
          root: Appearance(
            surface: Surface(fill: .term(brandFill)),
            content: Content(color: .term(t.color.action.content)),
          ),
          parts: {
            ButtonPart.icon: Appearance(
              surface: Surface(radius: .term(brandRadius)),
            ),
          },
          cases: [
            .when(
              state.hovered,
              Appearance(
                metrics: Metrics(padding: Insets.all(.term(t.radius.control))),
              ),
            ),
          ],
        ),
      ],
    ).validate();

    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.styleUnknownTerm,
        targetKind: 'term',
        targetName: 'color.brand.fill',
      ),
    );
    expect(
      diagnostics,
      containsDiagnostic(
        code: DiagnosticCodes.styleUnknownTerm,
        targetKind: 'term',
        targetName: 'radius.brand',
      ),
    );
    expect(
      diagnostics,
      isNot(
        containsDiagnostic(
          code: DiagnosticCodes.styleUnknownTerm,
          targetKind: 'term',
          targetName: 'radius.control',
        ),
      ),
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
      containsDiagnostic(code: DiagnosticCodes.bindingDuplicateAssignment),
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
      containsDiagnostic(code: DiagnosticCodes.styleUnknownPart),
    );
    expect(
      diagnostics,
      containsDiagnostic(code: DiagnosticCodes.styleUnknownAxis),
    );
    expect(
      diagnostics,
      containsDiagnostic(code: DiagnosticCodes.styleUnknownState),
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
      containsDiagnostic(code: DiagnosticCodes.identifierInvalidSegment),
    );
    expect(
      diagnostics,
      containsDiagnostic(code: DiagnosticCodes.identifierEmptySegment),
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
      containsDiagnostic(code: DiagnosticCodes.identifierDuplicate),
    );
  });

  test('runs custom policy objects', () {
    final diagnostics = Design(
      vocabulary: const _TermListVocabulary(),
      policies: const [_AlwaysReportPolicy()],
    ).validate();

    expect(
      diagnostics,
      containsDiagnostic(code: _AlwaysReportPolicy.codeValue),
    );
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
