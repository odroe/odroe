import 'package:odroe/style.dart';
import 'package:test/test.dart';

enum _ButtonPart { icon, label }

enum _ButtonTone { primary, danger }

enum _ButtonSize { sm, md }

enum _CardPart { header, body }

enum _SurfaceRole { canvas, raised, overlay }

enum _TextFieldPart { label, input, placeholder, helper, error }

const _buttonTone = Axis<_ButtonTone>(
  id: Identifier('button.tone'),
  defaultValue: _ButtonTone.primary,
);
const _buttonSize = Axis<_ButtonSize>(
  id: Identifier('button.size'),
  defaultValue: _ButtonSize.md,
);
const _surfaceRole = Axis<_SurfaceRole>(
  id: Identifier('surface.role'),
  defaultValue: _SurfaceRole.raised,
);

const _terms = _PressureTerms();

final _light = Binding(Identifier('light'), [
  _terms.color.surface.canvas(const Color(0xffffffff)),
  _terms.color.surface.raised(const Color(0xfff8f8f8)),
  _terms.color.surface.overlay(const Color(0xffffffff)),
  _terms.color.surface.stroke(const Color(0xffd8dee4)),
  _terms.color.surface.strokeStrong(const Color(0xff8c959f)),
  _terms.color.content.primary(const Color(0xff111111)),
  _terms.color.content.secondary(const Color(0xff57606a)),
  _terms.color.content.muted(const Color(0xff6e7781)),
  _terms.color.content.inverse(const Color(0xffffffff)),
  _terms.color.action.fill(const Color(0xff0969da)),
  _terms.color.action.fillHover(const Color(0xff0550ae)),
  _terms.color.action.fillPressed(const Color(0xff033d8b)),
  _terms.color.action.content(const Color(0xffffffff)),
  _terms.color.danger.fill(const Color(0xffcf222e)),
  _terms.color.danger.fillHover(const Color(0xffa40e26)),
  _terms.color.danger.content(const Color(0xffffffff)),
  _terms.color.danger.stroke(const Color(0xffcf222e)),
  _terms.color.field.fill(const Color(0xffffffff)),
  _terms.color.field.fillDisabled(const Color(0xfff6f8fa)),
  _terms.color.field.border(const Color(0xffd0d7de)),
  _terms.color.field.borderFocus(const Color(0xff0969da)),
  _terms.color.field.borderError(const Color(0xffcf222e)),
  _terms.color.field.placeholder(const Color(0xff6e7781)),
  _terms.color.field.helper(const Color(0xff57606a)),
  _terms.color.focus.ring(const Color(0xff54aeff)),
  _terms.space.controlX(16.px),
  _terms.space.controlY(8.px),
  _terms.space.controlSmX(12.px),
  _terms.space.controlSmY(6.px),
  _terms.space.inlineGap(8.px),
  _terms.space.fieldX(12.px),
  _terms.space.fieldY(8.px),
  _terms.space.fieldGap(6.px),
  _terms.space.surfacePadding(16.px),
  _terms.radius.control(8.px),
  _terms.radius.surface(12.px),
  _terms.radius.field(6.px),
  _terms.size.icon(18.px),
  _terms.size.iconSm(16.px),
  _terms.size.controlHeight(40.px),
  _terms.size.controlSmHeight(32.px),
  _terms.size.fieldHeight(40.px),
  _terms.size.cardMinWidth(280.px),
  _terms.elevation.none(0.px),
  _terms.elevation.raised(2.px),
  _terms.elevation.overlay(8.px),
  _terms.opacity.disabled(0.48),
  _terms.type.buttonLabel(const Identifier('text.buttonLabel')),
  _terms.type.buttonLabelSm(const Identifier('text.buttonLabelSm')),
  _terms.type.cardTitle(const Identifier('text.cardTitle')),
  _terms.type.cardBody(const Identifier('text.cardBody')),
  _terms.type.fieldLabel(const Identifier('text.fieldLabel')),
  _terms.type.fieldInput(const Identifier('text.fieldInput')),
  _terms.type.fieldHelper(const Identifier('text.fieldHelper')),
  _terms.type.fieldError(const Identifier('text.fieldError')),
  _terms.icon.buttonLeading(const Identifier('icon.buttonLeading')),
  _terms.icon.fieldError(const Identifier('icon.fieldError')),
]);

final _dark = Binding(Identifier('dark'), [
  _terms.color.surface.canvas(const Color(0xff0d1117)),
  _terms.color.surface.raised(const Color(0xff161b22)),
  _terms.color.surface.overlay(const Color(0xff21262d)),
  _terms.color.surface.stroke(const Color(0xff30363d)),
  _terms.color.surface.strokeStrong(const Color(0xff8b949e)),
  _terms.color.content.primary(const Color(0xfff0f6fc)),
  _terms.color.content.secondary(const Color(0xffc9d1d9)),
  _terms.color.content.muted(const Color(0xff8b949e)),
  _terms.color.content.inverse(const Color(0xff0d1117)),
  _terms.color.action.fill(const Color(0xff1f6feb)),
  _terms.color.action.fillHover(const Color(0xff388bfd)),
  _terms.color.action.fillPressed(const Color(0xff58a6ff)),
  _terms.color.action.content(const Color(0xffffffff)),
  _terms.color.danger.fill(const Color(0xffda3633)),
  _terms.color.danger.fillHover(const Color(0xffff7b72)),
  _terms.color.danger.content(const Color(0xff0d1117)),
  _terms.color.danger.stroke(const Color(0xffff7b72)),
  _terms.color.field.fill(const Color(0xff0d1117)),
  _terms.color.field.fillDisabled(const Color(0xff161b22)),
  _terms.color.field.border(const Color(0xff30363d)),
  _terms.color.field.borderFocus(const Color(0xff58a6ff)),
  _terms.color.field.borderError(const Color(0xffff7b72)),
  _terms.color.field.placeholder(const Color(0xff8b949e)),
  _terms.color.field.helper(const Color(0xffc9d1d9)),
  _terms.color.focus.ring(const Color(0xff1f6feb)),
  _terms.space.controlX(16.px),
  _terms.space.controlY(8.px),
  _terms.space.controlSmX(12.px),
  _terms.space.controlSmY(6.px),
  _terms.space.inlineGap(8.px),
  _terms.space.fieldX(12.px),
  _terms.space.fieldY(8.px),
  _terms.space.fieldGap(6.px),
  _terms.space.surfacePadding(16.px),
  _terms.radius.control(8.px),
  _terms.radius.surface(12.px),
  _terms.radius.field(6.px),
  _terms.size.icon(18.px),
  _terms.size.iconSm(16.px),
  _terms.size.controlHeight(40.px),
  _terms.size.controlSmHeight(32.px),
  _terms.size.fieldHeight(40.px),
  _terms.size.cardMinWidth(280.px),
  _terms.elevation.none(0.px),
  _terms.elevation.raised(2.px),
  _terms.elevation.overlay(8.px),
  _terms.opacity.disabled(0.52),
  _terms.type.buttonLabel(const Identifier('text.buttonLabel')),
  _terms.type.buttonLabelSm(const Identifier('text.buttonLabelSm')),
  _terms.type.cardTitle(const Identifier('text.cardTitle')),
  _terms.type.cardBody(const Identifier('text.cardBody')),
  _terms.type.fieldLabel(const Identifier('text.fieldLabel')),
  _terms.type.fieldInput(const Identifier('text.fieldInput')),
  _terms.type.fieldHelper(const Identifier('text.fieldHelper')),
  _terms.type.fieldError(const Identifier('text.fieldError')),
  _terms.icon.buttonLeading(const Identifier('icon.buttonLeading')),
  _terms.icon.fieldError(const Identifier('icon.fieldError')),
]);

final _button = Style<_ButtonPart>(
  id: Identifier('button'),
  contract: Contract<_ButtonPart>(
    parts: {_ButtonPart.icon, _ButtonPart.label},
    axes: [_buttonTone, _buttonSize],
    states: {state.hovered, state.pressed, state.disabled, state.focusVisible},
  ),
  root: Appearance(
    surface: Surface(
      fill: .term(_terms.color.action.fill),
      radius: .term(_terms.radius.control),
    ),
    content: Content(
      color: .term(_terms.color.action.content),
      text: .term(_terms.type.buttonLabel),
    ),
    metrics: Metrics(
      padding: Insets.symmetric(
        x: .term(_terms.space.controlX),
        y: .term(_terms.space.controlY),
      ),
      gap: .term(_terms.space.inlineGap),
      minHeight: .term(_terms.size.controlHeight),
    ),
  ),
  parts: {
    _ButtonPart.icon: Appearance(
      content: Content(icon: .term(_terms.icon.buttonLeading)),
      metrics: Metrics(width: .term(_terms.size.icon)),
    ),
    _ButtonPart.label: Appearance(
      content: Content(text: .term(_terms.type.buttonLabel)),
    ),
  },
  cases: [
    .when(
      _buttonSize(.sm),
      Appearance(
        content: Content(text: .term(_terms.type.buttonLabelSm)),
        metrics: Metrics(
          padding: Insets.symmetric(
            x: .term(_terms.space.controlSmX),
            y: .term(_terms.space.controlSmY),
          ),
          width: .term(_terms.size.iconSm),
          minHeight: .term(_terms.size.controlSmHeight),
        ),
      ),
    ),
    .when(
      state.hovered,
      Appearance(surface: Surface(fill: .term(_terms.color.action.fillHover))),
    ),
    .when(
      state.pressed,
      Appearance(
        surface: Surface(fill: .term(_terms.color.action.fillPressed)),
      ),
    ),
    .when(
      _buttonTone(.danger),
      Appearance(
        surface: Surface(fill: .term(_terms.color.danger.fill)),
        content: Content(color: .term(_terms.color.danger.content)),
      ),
    ),
    .all(
      [_buttonTone(.danger), state.hovered],
      Appearance(surface: Surface(fill: .term(_terms.color.danger.fillHover))),
    ),
    .when(
      state.focusVisible,
      Appearance(surface: Surface(stroke: .term(_terms.color.focus.ring))),
    ),
    .when(
      state.disabled,
      Appearance(content: Content(opacity: .term(_terms.opacity.disabled))),
    ),
  ],
);

final _card = Style<_CardPart>(
  id: Identifier('card'),
  contract: Contract<_CardPart>(
    parts: {_CardPart.header, _CardPart.body},
    axes: [_surfaceRole],
    states: {state.hovered, state.focusVisible},
  ),
  root: Appearance(
    surface: Surface(
      fill: .term(_terms.color.surface.raised),
      stroke: .term(_terms.color.surface.stroke),
      radius: .term(_terms.radius.surface),
      elevation: .term(_terms.elevation.raised),
    ),
    content: Content(color: .term(_terms.color.content.primary)),
    metrics: Metrics(
      padding: Insets.all(.term(_terms.space.surfacePadding)),
      minWidth: .term(_terms.size.cardMinWidth),
    ),
  ),
  parts: {
    _CardPart.header: Appearance(
      content: Content(
        color: .term(_terms.color.content.primary),
        text: .term(_terms.type.cardTitle),
      ),
    ),
    _CardPart.body: Appearance(
      content: Content(
        color: .term(_terms.color.content.secondary),
        text: .term(_terms.type.cardBody),
      ),
    ),
  },
  cases: [
    .when(
      _surfaceRole(.canvas),
      Appearance(
        surface: Surface(
          fill: .term(_terms.color.surface.canvas),
          elevation: .term(_terms.elevation.none),
        ),
      ),
    ),
    .when(
      _surfaceRole(.overlay),
      Appearance(
        surface: Surface(
          fill: .term(_terms.color.surface.overlay),
          stroke: .term(_terms.color.surface.strokeStrong),
          elevation: .term(_terms.elevation.overlay),
        ),
      ),
    ),
    .when(
      state.hovered,
      Appearance(
        surface: Surface(stroke: .term(_terms.color.surface.strokeStrong)),
      ),
    ),
    .when(
      state.focusVisible,
      Appearance(surface: Surface(stroke: .term(_terms.color.focus.ring))),
    ),
  ],
);

final _textField = Style<_TextFieldPart>(
  id: Identifier('textField'),
  contract: Contract<_TextFieldPart>(
    parts: {
      _TextFieldPart.label,
      _TextFieldPart.input,
      _TextFieldPart.placeholder,
      _TextFieldPart.helper,
      _TextFieldPart.error,
    },
    states: {state.focused, state.focusVisible, state.disabled, state.error},
  ),
  root: Appearance(
    surface: Surface(
      fill: .term(_terms.color.field.fill),
      stroke: .term(_terms.color.field.border),
      radius: .term(_terms.radius.field),
    ),
    content: Content(color: .term(_terms.color.content.primary)),
    metrics: Metrics(
      padding: Insets.symmetric(
        x: .term(_terms.space.fieldX),
        y: .term(_terms.space.fieldY),
      ),
      gap: .term(_terms.space.fieldGap),
      minHeight: .term(_terms.size.fieldHeight),
    ),
  ),
  parts: {
    _TextFieldPart.label: Appearance(
      content: Content(
        color: .term(_terms.color.content.secondary),
        text: .term(_terms.type.fieldLabel),
      ),
    ),
    _TextFieldPart.input: Appearance(
      content: Content(
        color: .term(_terms.color.content.primary),
        text: .term(_terms.type.fieldInput),
      ),
    ),
    _TextFieldPart.placeholder: Appearance(
      content: Content(
        color: .term(_terms.color.field.placeholder),
        text: .term(_terms.type.fieldInput),
      ),
    ),
    _TextFieldPart.helper: Appearance(
      content: Content(
        color: .term(_terms.color.field.helper),
        text: .term(_terms.type.fieldHelper),
      ),
    ),
    _TextFieldPart.error: Appearance(
      content: Content(
        color: .term(_terms.color.danger.stroke),
        icon: .term(_terms.icon.fieldError),
        text: .term(_terms.type.fieldError),
      ),
    ),
  },
  cases: [
    .when(
      state.focused,
      Appearance(
        surface: Surface(stroke: .term(_terms.color.field.borderFocus)),
      ),
    ),
    .when(
      state.focusVisible,
      Appearance(surface: Surface(stroke: .term(_terms.color.focus.ring))),
    ),
    .when(
      state.error,
      Appearance(
        surface: Surface(stroke: .term(_terms.color.field.borderError)),
        content: Content(color: .term(_terms.color.danger.stroke)),
      ),
    ),
    .when(
      state.disabled,
      Appearance(
        surface: Surface(fill: .term(_terms.color.field.fillDisabled)),
        content: Content(opacity: .term(_terms.opacity.disabled)),
      ),
    ),
  ],
);

final _design = Design(
  vocabulary: _terms,
  bindings: [_light, _dark],
  styles: [_button, _card, _textField],
  policies: const [_PressurePolicy()],
);

void main() {
  test('validates representative platform-neutral style examples', () {
    final diagnostics = _design.validate();

    expect(diagnostics.map((diagnostic) => diagnostic.toString()), isEmpty);
    expect(_design.bindings.map((binding) => binding.id.value), [
      'light',
      'dark',
    ]);
    expect(_design.styles.map((style) => style.id.value), [
      'button',
      'card',
      'textField',
    ]);
  });

  test('resolves button parts states and axes from the public style API', () {
    final resolution = _button.resolve(
      binding: _dark,
      part: _ButtonPart.icon,
      states: [state.hovered, state.focusVisible],
      axisValues: [_buttonTone(.danger), _buttonSize(.sm)],
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

  test('resolves card surface roles across light and nested dark bindings', () {
    final lightRaised = _card.resolve(binding: _light);
    final darkOverlay = _card.resolve(
      binding: _dark,
      part: _CardPart.header,
      axisValues: [_surfaceRole(.overlay)],
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
    final placeholder = _textField.resolve(
      binding: _light,
      part: _TextFieldPart.placeholder,
    );
    final focusedError = _textField.resolve(
      binding: _light,
      part: _TextFieldPart.error,
      states: [state.focused, state.error],
    );
    final disabledInput = _textField.resolve(
      binding: _dark,
      part: _TextFieldPart.input,
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

final class _PressurePolicy implements Policy {
  const _PressurePolicy();

  @override
  String get code => 'example.style_pressure';

  @override
  void evaluate(PolicyContext context) {
    final design = context.design;
    final bindingIds = {for (final binding in design.bindings) binding.id};
    final styleIds = {for (final style in design.styles) style.id};

    if (!bindingIds.contains(const Identifier('dark'))) {
      context.report(
        const Diagnostic(
          code: 'example.missing_dark_binding',
          severity: DiagnosticSeverity.warning,
          message: 'Pressure examples should include a dark binding.',
        ),
      );
    }

    if (!styleIds.contains(const Identifier('textField'))) {
      context.report(
        const Diagnostic(
          code: 'example.missing_text_field',
          severity: DiagnosticSeverity.warning,
          message: 'Pressure examples should include a text field style.',
        ),
      );
    }
  }
}

final class _PressureTerms implements Vocabulary {
  const _PressureTerms();

  _ColorTerms get color => const _ColorTerms();

  _SpaceTerms get space => const _SpaceTerms();

  _RadiusTerms get radius => const _RadiusTerms();

  _SizeTerms get size => const _SizeTerms();

  _ElevationTerms get elevation => const _ElevationTerms();

  _OpacityTerms get opacity => const _OpacityTerms();

  _TypeTerms get type => const _TypeTerms();

  _IconTerms get icon => const _IconTerms();

  @override
  Iterable<Term> get terms => [
    ...color.terms,
    ...space.terms,
    ...radius.terms,
    ...size.terms,
    ...elevation.terms,
    ...opacity.terms,
    ...type.terms,
    ...icon.terms,
  ];
}

final class _ColorTerms implements Vocabulary {
  const _ColorTerms();

  _SurfaceColorTerms get surface => const _SurfaceColorTerms();

  _ContentColorTerms get content => const _ContentColorTerms();

  _ActionColorTerms get action => const _ActionColorTerms();

  _DangerColorTerms get danger => const _DangerColorTerms();

  _FieldColorTerms get field => const _FieldColorTerms();

  _FocusColorTerms get focus => const _FocusColorTerms();

  @override
  Iterable<Term> get terms => [
    ...surface.terms,
    ...content.terms,
    ...action.terms,
    ...danger.terms,
    ...field.terms,
    ...focus.terms,
  ];
}

final class _SurfaceColorTerms implements Vocabulary {
  const _SurfaceColorTerms();

  Term<Color> get canvas => const Term(Identifier('color.surface.canvas'));

  Term<Color> get raised => const Term(Identifier('color.surface.raised'));

  Term<Color> get overlay => const Term(Identifier('color.surface.overlay'));

  Term<Color> get stroke => const Term(Identifier('color.surface.stroke'));

  Term<Color> get strokeStrong =>
      const Term(Identifier('color.surface.strokeStrong'));

  @override
  Iterable<Term> get terms => [canvas, raised, overlay, stroke, strokeStrong];
}

final class _ContentColorTerms implements Vocabulary {
  const _ContentColorTerms();

  Term<Color> get primary => const Term(Identifier('color.content.primary'));

  Term<Color> get secondary =>
      const Term(Identifier('color.content.secondary'));

  Term<Color> get muted => const Term(Identifier('color.content.muted'));

  Term<Color> get inverse => const Term(Identifier('color.content.inverse'));

  @override
  Iterable<Term> get terms => [primary, secondary, muted, inverse];
}

final class _ActionColorTerms implements Vocabulary {
  const _ActionColorTerms();

  Term<Color> get fill => const Term(Identifier('color.action.fill'));

  Term<Color> get fillHover => const Term(Identifier('color.action.fillHover'));

  Term<Color> get fillPressed =>
      const Term(Identifier('color.action.fillPressed'));

  Term<Color> get content => const Term(Identifier('color.action.content'));

  @override
  Iterable<Term> get terms => [fill, fillHover, fillPressed, content];
}

final class _DangerColorTerms implements Vocabulary {
  const _DangerColorTerms();

  Term<Color> get fill => const Term(Identifier('color.danger.fill'));

  Term<Color> get fillHover => const Term(Identifier('color.danger.fillHover'));

  Term<Color> get content => const Term(Identifier('color.danger.content'));

  Term<Color> get stroke => const Term(Identifier('color.danger.stroke'));

  @override
  Iterable<Term> get terms => [fill, fillHover, content, stroke];
}

final class _FieldColorTerms implements Vocabulary {
  const _FieldColorTerms();

  Term<Color> get fill => const Term(Identifier('color.field.fill'));

  Term<Color> get fillDisabled =>
      const Term(Identifier('color.field.fillDisabled'));

  Term<Color> get border => const Term(Identifier('color.field.border'));

  Term<Color> get borderFocus =>
      const Term(Identifier('color.field.borderFocus'));

  Term<Color> get borderError =>
      const Term(Identifier('color.field.borderError'));

  Term<Color> get placeholder =>
      const Term(Identifier('color.field.placeholder'));

  Term<Color> get helper => const Term(Identifier('color.field.helper'));

  @override
  Iterable<Term> get terms => [
    fill,
    fillDisabled,
    border,
    borderFocus,
    borderError,
    placeholder,
    helper,
  ];
}

final class _FocusColorTerms implements Vocabulary {
  const _FocusColorTerms();

  Term<Color> get ring => const Term(Identifier('color.focus.ring'));

  @override
  Iterable<Term> get terms => [ring];
}

final class _SpaceTerms implements Vocabulary {
  const _SpaceTerms();

  Term<Dimension> get controlX => const Term(Identifier('space.controlX'));

  Term<Dimension> get controlY => const Term(Identifier('space.controlY'));

  Term<Dimension> get controlSmX => const Term(Identifier('space.controlSmX'));

  Term<Dimension> get controlSmY => const Term(Identifier('space.controlSmY'));

  Term<Dimension> get inlineGap => const Term(Identifier('space.inlineGap'));

  Term<Dimension> get fieldX => const Term(Identifier('space.fieldX'));

  Term<Dimension> get fieldY => const Term(Identifier('space.fieldY'));

  Term<Dimension> get fieldGap => const Term(Identifier('space.fieldGap'));

  Term<Dimension> get surfacePadding =>
      const Term(Identifier('space.surfacePadding'));

  @override
  Iterable<Term> get terms => [
    controlX,
    controlY,
    controlSmX,
    controlSmY,
    inlineGap,
    fieldX,
    fieldY,
    fieldGap,
    surfacePadding,
  ];
}

final class _RadiusTerms implements Vocabulary {
  const _RadiusTerms();

  Term<Dimension> get control => const Term(Identifier('radius.control'));

  Term<Dimension> get surface => const Term(Identifier('radius.surface'));

  Term<Dimension> get field => const Term(Identifier('radius.field'));

  @override
  Iterable<Term> get terms => [control, surface, field];
}

final class _SizeTerms implements Vocabulary {
  const _SizeTerms();

  Term<Dimension> get icon => const Term(Identifier('size.icon'));

  Term<Dimension> get iconSm => const Term(Identifier('size.iconSm'));

  Term<Dimension> get controlHeight =>
      const Term(Identifier('size.controlHeight'));

  Term<Dimension> get controlSmHeight =>
      const Term(Identifier('size.controlSmHeight'));

  Term<Dimension> get fieldHeight => const Term(Identifier('size.fieldHeight'));

  Term<Dimension> get cardMinWidth =>
      const Term(Identifier('size.cardMinWidth'));

  @override
  Iterable<Term> get terms => [
    icon,
    iconSm,
    controlHeight,
    controlSmHeight,
    fieldHeight,
    cardMinWidth,
  ];
}

final class _ElevationTerms implements Vocabulary {
  const _ElevationTerms();

  Term<Dimension> get none => const Term(Identifier('elevation.none'));

  Term<Dimension> get raised => const Term(Identifier('elevation.raised'));

  Term<Dimension> get overlay => const Term(Identifier('elevation.overlay'));

  @override
  Iterable<Term> get terms => [none, raised, overlay];
}

final class _OpacityTerms implements Vocabulary {
  const _OpacityTerms();

  Term<double> get disabled => const Term(Identifier('opacity.disabled'));

  @override
  Iterable<Term> get terms => [disabled];
}

final class _TypeTerms implements Vocabulary {
  const _TypeTerms();

  Term<Identifier> get buttonLabel =>
      const Term(Identifier('type.buttonLabel'));

  Term<Identifier> get buttonLabelSm =>
      const Term(Identifier('type.buttonLabelSm'));

  Term<Identifier> get cardTitle => const Term(Identifier('type.cardTitle'));

  Term<Identifier> get cardBody => const Term(Identifier('type.cardBody'));

  Term<Identifier> get fieldLabel => const Term(Identifier('type.fieldLabel'));

  Term<Identifier> get fieldInput => const Term(Identifier('type.fieldInput'));

  Term<Identifier> get fieldHelper =>
      const Term(Identifier('type.fieldHelper'));

  Term<Identifier> get fieldError => const Term(Identifier('type.fieldError'));

  @override
  Iterable<Term> get terms => [
    buttonLabel,
    buttonLabelSm,
    cardTitle,
    cardBody,
    fieldLabel,
    fieldInput,
    fieldHelper,
    fieldError,
  ];
}

final class _IconTerms implements Vocabulary {
  const _IconTerms();

  Term<Identifier> get buttonLeading =>
      const Term(Identifier('icon.buttonLeading'));

  Term<Identifier> get fieldError => const Term(Identifier('icon.fieldError'));

  @override
  Iterable<Term> get terms => [buttonLeading, fieldError];
}
