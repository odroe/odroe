import 'package:odroe/style.dart';

enum ButtonPart { icon, label }

enum ButtonTone { primary, danger }

enum ButtonSize { sm, md }

enum CardPart { header, body }

enum SurfaceRole { canvas, raised, overlay }

enum TextFieldPart { label, input, placeholder, helper, error }

const buttonTone = Axis<ButtonTone>(
  id: Identifier('button.tone'),
  defaultValue: ButtonTone.primary,
);
const buttonSize = Axis<ButtonSize>(
  id: Identifier('button.size'),
  defaultValue: ButtonSize.md,
);
const surfaceRole = Axis<SurfaceRole>(
  id: Identifier('surface.role'),
  defaultValue: SurfaceRole.raised,
);

const terms = AppTerms();

final noShadow = Shadow([]);

final raisedShadow = Shadow([
  const ShadowLayer(
    color: Color(0x1f000000),
    offsetX: Dimension.px(0),
    offsetY: Dimension.px(2),
    blur: Dimension.px(8),
  ),
]);

final overlayShadow = Shadow([
  const ShadowLayer(
    color: Color(0x29000000),
    offsetX: Dimension.px(0),
    offsetY: Dimension.px(8),
    blur: Dimension.px(24),
  ),
]);

final light = Binding(Identifier('light'), [
  terms.color.surface.canvas(const Color(0xffffffff)),
  terms.color.surface.raised(const Color(0xfff8f8f8)),
  terms.color.surface.overlay(const Color(0xffffffff)),
  terms.color.surface.stroke(const Color(0xffd8dee4)),
  terms.color.surface.strokeStrong(const Color(0xff8c959f)),
  terms.color.content.primary(const Color(0xff111111)),
  terms.color.content.secondary(const Color(0xff57606a)),
  terms.color.content.muted(const Color(0xff6e7781)),
  terms.color.content.inverse(const Color(0xffffffff)),
  terms.color.action.fill(const Color(0xff0969da)),
  terms.color.action.fillHover(const Color(0xff0550ae)),
  terms.color.action.fillPressed(const Color(0xff033d8b)),
  terms.color.action.content(const Color(0xffffffff)),
  terms.color.danger.fill(const Color(0xffcf222e)),
  terms.color.danger.fillHover(const Color(0xffa40e26)),
  terms.color.danger.content(const Color(0xffffffff)),
  terms.color.danger.stroke(const Color(0xffcf222e)),
  terms.color.field.fill(const Color(0xffffffff)),
  terms.color.field.fillDisabled(const Color(0xfff6f8fa)),
  terms.color.field.border(const Color(0xffd0d7de)),
  terms.color.field.borderFocus(const Color(0xff0969da)),
  terms.color.field.borderError(const Color(0xffcf222e)),
  terms.color.field.placeholder(const Color(0xff6e7781)),
  terms.color.field.helper(const Color(0xff57606a)),
  terms.color.focus.ring(const Color(0xff54aeff)),
  terms.space.controlX(16.px),
  terms.space.controlY(8.px),
  terms.space.controlSmX(12.px),
  terms.space.controlSmY(6.px),
  terms.space.inlineGap(8.px),
  terms.space.fieldX(12.px),
  terms.space.fieldY(8.px),
  terms.space.fieldGap(6.px),
  terms.space.surfacePadding(16.px),
  terms.radius.control(8.px),
  terms.radius.surface(12.px),
  terms.radius.field(6.px),
  terms.stroke.width(1.px),
  terms.stroke.focusWidth(2.px),
  terms.stroke.style(StrokeStyle.solid),
  terms.size.icon(18.px),
  terms.size.iconSm(16.px),
  terms.size.controlHeight(40.px),
  terms.size.controlSmHeight(32.px),
  terms.size.fieldHeight(40.px),
  terms.size.cardMinWidth(280.px),
  terms.shadow.none(noShadow),
  terms.shadow.raised(raisedShadow),
  terms.shadow.overlay(overlayShadow),
  terms.opacity.disabled(0.48),
  terms.type.buttonLabel(const Identifier('text.buttonLabel')),
  terms.type.buttonLabelSm(const Identifier('text.buttonLabelSm')),
  terms.type.cardTitle(const Identifier('text.cardTitle')),
  terms.type.cardBody(const Identifier('text.cardBody')),
  terms.type.fieldLabel(const Identifier('text.fieldLabel')),
  terms.type.fieldInput(const Identifier('text.fieldInput')),
  terms.type.fieldHelper(const Identifier('text.fieldHelper')),
  terms.type.fieldError(const Identifier('text.fieldError')),
  terms.icon.buttonLeading(const Identifier('icon.buttonLeading')),
  terms.icon.fieldError(const Identifier('icon.fieldError')),
]);

final dark = Binding(Identifier('dark'), [
  terms.color.surface.canvas(const Color(0xff0d1117)),
  terms.color.surface.raised(const Color(0xff161b22)),
  terms.color.surface.overlay(const Color(0xff21262d)),
  terms.color.surface.stroke(const Color(0xff30363d)),
  terms.color.surface.strokeStrong(const Color(0xff8b949e)),
  terms.color.content.primary(const Color(0xfff0f6fc)),
  terms.color.content.secondary(const Color(0xffc9d1d9)),
  terms.color.content.muted(const Color(0xff8b949e)),
  terms.color.content.inverse(const Color(0xff0d1117)),
  terms.color.action.fill(const Color(0xff1f6feb)),
  terms.color.action.fillHover(const Color(0xff388bfd)),
  terms.color.action.fillPressed(const Color(0xff58a6ff)),
  terms.color.action.content(const Color(0xffffffff)),
  terms.color.danger.fill(const Color(0xffda3633)),
  terms.color.danger.fillHover(const Color(0xffff7b72)),
  terms.color.danger.content(const Color(0xff0d1117)),
  terms.color.danger.stroke(const Color(0xffff7b72)),
  terms.color.field.fill(const Color(0xff0d1117)),
  terms.color.field.fillDisabled(const Color(0xff161b22)),
  terms.color.field.border(const Color(0xff30363d)),
  terms.color.field.borderFocus(const Color(0xff58a6ff)),
  terms.color.field.borderError(const Color(0xffff7b72)),
  terms.color.field.placeholder(const Color(0xff8b949e)),
  terms.color.field.helper(const Color(0xffc9d1d9)),
  terms.color.focus.ring(const Color(0xff1f6feb)),
  terms.space.controlX(16.px),
  terms.space.controlY(8.px),
  terms.space.controlSmX(12.px),
  terms.space.controlSmY(6.px),
  terms.space.inlineGap(8.px),
  terms.space.fieldX(12.px),
  terms.space.fieldY(8.px),
  terms.space.fieldGap(6.px),
  terms.space.surfacePadding(16.px),
  terms.radius.control(8.px),
  terms.radius.surface(12.px),
  terms.radius.field(6.px),
  terms.stroke.width(1.px),
  terms.stroke.focusWidth(2.px),
  terms.stroke.style(StrokeStyle.solid),
  terms.size.icon(18.px),
  terms.size.iconSm(16.px),
  terms.size.controlHeight(40.px),
  terms.size.controlSmHeight(32.px),
  terms.size.fieldHeight(40.px),
  terms.size.cardMinWidth(280.px),
  terms.shadow.none(noShadow),
  terms.shadow.raised(raisedShadow),
  terms.shadow.overlay(overlayShadow),
  terms.opacity.disabled(0.52),
  terms.type.buttonLabel(const Identifier('text.buttonLabel')),
  terms.type.buttonLabelSm(const Identifier('text.buttonLabelSm')),
  terms.type.cardTitle(const Identifier('text.cardTitle')),
  terms.type.cardBody(const Identifier('text.cardBody')),
  terms.type.fieldLabel(const Identifier('text.fieldLabel')),
  terms.type.fieldInput(const Identifier('text.fieldInput')),
  terms.type.fieldHelper(const Identifier('text.fieldHelper')),
  terms.type.fieldError(const Identifier('text.fieldError')),
  terms.icon.buttonLeading(const Identifier('icon.buttonLeading')),
  terms.icon.fieldError(const Identifier('icon.fieldError')),
]);

final button = Style<ButtonPart>(
  id: Identifier('button'),
  contract: Contract<ButtonPart>(
    parts: {ButtonPart.icon, ButtonPart.label},
    axes: [buttonTone, buttonSize],
    states: {state.hovered, state.pressed, state.disabled, state.focusVisible},
  ),
  root: Appearance(
    surface: Surface(
      fill: .term(terms.color.action.fill),
      radius: .term(terms.radius.control),
    ),
    content: Content(
      color: .term(terms.color.action.content),
      text: .term(terms.type.buttonLabel),
    ),
    metrics: Metrics(
      padding: Insets.symmetric(
        x: .term(terms.space.controlX),
        y: .term(terms.space.controlY),
      ),
      gap: .term(terms.space.inlineGap),
      minHeight: .term(terms.size.controlHeight),
    ),
  ),
  parts: {
    ButtonPart.icon: Appearance(
      content: Content(icon: .term(terms.icon.buttonLeading)),
      metrics: Metrics(width: .term(terms.size.icon)),
    ),
    ButtonPart.label: Appearance(
      content: Content(text: .term(terms.type.buttonLabel)),
    ),
  },
  cases: [
    .when(
      buttonSize(.sm),
      Appearance(
        content: Content(text: .term(terms.type.buttonLabelSm)),
        metrics: Metrics(
          padding: Insets.symmetric(
            x: .term(terms.space.controlSmX),
            y: .term(terms.space.controlSmY),
          ),
          width: .term(terms.size.iconSm),
          minHeight: .term(terms.size.controlSmHeight),
        ),
      ),
    ),
    .when(
      state.hovered,
      Appearance(surface: Surface(fill: .term(terms.color.action.fillHover))),
    ),
    .when(
      state.pressed,
      Appearance(surface: Surface(fill: .term(terms.color.action.fillPressed))),
    ),
    .when(
      buttonTone(.danger),
      Appearance(
        surface: Surface(fill: .term(terms.color.danger.fill)),
        content: Content(color: .term(terms.color.danger.content)),
      ),
    ),
    .all([
      buttonTone(.danger),
      state.hovered,
    ], Appearance(surface: Surface(fill: .term(terms.color.danger.fillHover)))),
    .when(
      state.focusVisible,
      Appearance(
        surface: Surface(
          stroke: Stroke(
            color: .term(terms.color.focus.ring),
            width: .term(terms.stroke.focusWidth),
            style: .term(terms.stroke.style),
          ),
        ),
      ),
    ),
    .when(
      state.disabled,
      Appearance(content: Content(opacity: .term(terms.opacity.disabled))),
    ),
  ],
);

final card = Style<CardPart>(
  id: Identifier('card'),
  contract: Contract<CardPart>(
    parts: {CardPart.header, CardPart.body},
    axes: [surfaceRole],
    states: {state.hovered, state.focusVisible},
  ),
  root: Appearance(
    surface: Surface(
      fill: .term(terms.color.surface.raised),
      stroke: Stroke(
        color: .term(terms.color.surface.stroke),
        width: .term(terms.stroke.width),
        style: .term(terms.stroke.style),
      ),
      radius: .term(terms.radius.surface),
      shadow: .term(terms.shadow.raised),
    ),
    content: Content(color: .term(terms.color.content.primary)),
    metrics: Metrics(
      padding: Insets.all(.term(terms.space.surfacePadding)),
      minWidth: .term(terms.size.cardMinWidth),
    ),
  ),
  parts: {
    CardPart.header: Appearance(
      content: Content(
        color: .term(terms.color.content.primary),
        text: .term(terms.type.cardTitle),
      ),
    ),
    CardPart.body: Appearance(
      content: Content(
        color: .term(terms.color.content.secondary),
        text: .term(terms.type.cardBody),
      ),
    ),
  },
  cases: [
    .when(
      surfaceRole(.canvas),
      Appearance(
        surface: Surface(
          fill: .term(terms.color.surface.canvas),
          shadow: .term(terms.shadow.none),
        ),
      ),
    ),
    .when(
      surfaceRole(.overlay),
      Appearance(
        surface: Surface(
          fill: .term(terms.color.surface.overlay),
          stroke: Stroke(color: .term(terms.color.surface.strokeStrong)),
          shadow: .term(terms.shadow.overlay),
        ),
      ),
    ),
    .when(
      state.hovered,
      Appearance(
        surface: Surface(
          stroke: Stroke(color: .term(terms.color.surface.strokeStrong)),
        ),
      ),
    ),
    .when(
      state.focusVisible,
      Appearance(
        surface: Surface(stroke: Stroke(color: .term(terms.color.focus.ring))),
      ),
    ),
  ],
);

final textField = Style<TextFieldPart>(
  id: Identifier('textField'),
  contract: Contract<TextFieldPart>(
    parts: {
      TextFieldPart.label,
      TextFieldPart.input,
      TextFieldPart.placeholder,
      TextFieldPart.helper,
      TextFieldPart.error,
    },
    states: {state.focused, state.focusVisible, state.disabled, state.error},
  ),
  root: Appearance(
    surface: Surface(
      fill: .term(terms.color.field.fill),
      stroke: Stroke(
        color: .term(terms.color.field.border),
        width: .term(terms.stroke.width),
        style: .term(terms.stroke.style),
      ),
      radius: .term(terms.radius.field),
    ),
    content: Content(color: .term(terms.color.content.primary)),
    metrics: Metrics(
      padding: Insets.symmetric(
        x: .term(terms.space.fieldX),
        y: .term(terms.space.fieldY),
      ),
      gap: .term(terms.space.fieldGap),
      minHeight: .term(terms.size.fieldHeight),
    ),
  ),
  parts: {
    TextFieldPart.label: Appearance(
      content: Content(
        color: .term(terms.color.content.secondary),
        text: .term(terms.type.fieldLabel),
      ),
    ),
    TextFieldPart.input: Appearance(
      content: Content(
        color: .term(terms.color.content.primary),
        text: .term(terms.type.fieldInput),
      ),
    ),
    TextFieldPart.placeholder: Appearance(
      content: Content(
        color: .term(terms.color.field.placeholder),
        text: .term(terms.type.fieldInput),
      ),
    ),
    TextFieldPart.helper: Appearance(
      content: Content(
        color: .term(terms.color.field.helper),
        text: .term(terms.type.fieldHelper),
      ),
    ),
    TextFieldPart.error: Appearance(
      content: Content(
        color: .term(terms.color.danger.stroke),
        icon: .term(terms.icon.fieldError),
        text: .term(terms.type.fieldError),
      ),
    ),
  },
  cases: [
    .when(
      state.focused,
      Appearance(
        surface: Surface(
          stroke: Stroke(color: .term(terms.color.field.borderFocus)),
        ),
      ),
    ),
    .when(
      state.focusVisible,
      Appearance(
        surface: Surface(stroke: Stroke(color: .term(terms.color.focus.ring))),
      ),
    ),
    .when(
      state.error,
      Appearance(
        surface: Surface(
          stroke: Stroke(color: .term(terms.color.field.borderError)),
        ),
        content: Content(color: .term(terms.color.danger.stroke)),
      ),
    ),
    .when(
      state.disabled,
      Appearance(
        surface: Surface(fill: .term(terms.color.field.fillDisabled)),
        content: Content(opacity: .term(terms.opacity.disabled)),
      ),
    ),
  ],
);

final design = Design(
  vocabulary: terms,
  bindings: [light, dark],
  styles: [button, card, textField],
  policies: const [StylePrimitivesPolicy()],
);

String formatColor(Color? color) {
  if (color == null) {
    return 'none';
  }

  return '0x${color.toARGB32().toRadixString(16).padLeft(8, '0')}';
}

String formatDimension(Dimension? dimension) {
  return switch (dimension) {
    PixelDimension(:final value) => '${value}px',
    null => 'none',
  };
}

final class StylePrimitivesPolicy implements Policy {
  const StylePrimitivesPolicy();

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

final class AppTerms implements Vocabulary {
  const AppTerms();

  ColorTerms get color => const ColorTerms();

  SpaceTerms get space => const SpaceTerms();

  RadiusTerms get radius => const RadiusTerms();

  StrokeTerms get stroke => const StrokeTerms();

  SizeTerms get size => const SizeTerms();

  ShadowTerms get shadow => const ShadowTerms();

  OpacityTerms get opacity => const OpacityTerms();

  TypeTerms get type => const TypeTerms();

  IconTerms get icon => const IconTerms();

  @override
  Iterable<Term> get terms => [
    ...color.terms,
    ...space.terms,
    ...radius.terms,
    ...stroke.terms,
    ...size.terms,
    ...shadow.terms,
    ...opacity.terms,
    ...type.terms,
    ...icon.terms,
  ];
}

final class ColorTerms implements Vocabulary {
  const ColorTerms();

  SurfaceColorTerms get surface => const SurfaceColorTerms();

  ContentColorTerms get content => const ContentColorTerms();

  ActionColorTerms get action => const ActionColorTerms();

  DangerColorTerms get danger => const DangerColorTerms();

  FieldColorTerms get field => const FieldColorTerms();

  FocusColorTerms get focus => const FocusColorTerms();

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

final class SurfaceColorTerms implements Vocabulary {
  const SurfaceColorTerms();

  Term<Color> get canvas => const Term(Identifier('color.surface.canvas'));

  Term<Color> get raised => const Term(Identifier('color.surface.raised'));

  Term<Color> get overlay => const Term(Identifier('color.surface.overlay'));

  Term<Color> get stroke => const Term(Identifier('color.surface.stroke'));

  Term<Color> get strokeStrong =>
      const Term(Identifier('color.surface.strokeStrong'));

  @override
  Iterable<Term> get terms => [canvas, raised, overlay, stroke, strokeStrong];
}

final class ContentColorTerms implements Vocabulary {
  const ContentColorTerms();

  Term<Color> get primary => const Term(Identifier('color.content.primary'));

  Term<Color> get secondary =>
      const Term(Identifier('color.content.secondary'));

  Term<Color> get muted => const Term(Identifier('color.content.muted'));

  Term<Color> get inverse => const Term(Identifier('color.content.inverse'));

  @override
  Iterable<Term> get terms => [primary, secondary, muted, inverse];
}

final class ActionColorTerms implements Vocabulary {
  const ActionColorTerms();

  Term<Color> get fill => const Term(Identifier('color.action.fill'));

  Term<Color> get fillHover => const Term(Identifier('color.action.fillHover'));

  Term<Color> get fillPressed =>
      const Term(Identifier('color.action.fillPressed'));

  Term<Color> get content => const Term(Identifier('color.action.content'));

  @override
  Iterable<Term> get terms => [fill, fillHover, fillPressed, content];
}

final class DangerColorTerms implements Vocabulary {
  const DangerColorTerms();

  Term<Color> get fill => const Term(Identifier('color.danger.fill'));

  Term<Color> get fillHover => const Term(Identifier('color.danger.fillHover'));

  Term<Color> get content => const Term(Identifier('color.danger.content'));

  Term<Color> get stroke => const Term(Identifier('color.danger.stroke'));

  @override
  Iterable<Term> get terms => [fill, fillHover, content, stroke];
}

final class FieldColorTerms implements Vocabulary {
  const FieldColorTerms();

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

final class FocusColorTerms implements Vocabulary {
  const FocusColorTerms();

  Term<Color> get ring => const Term(Identifier('color.focus.ring'));

  @override
  Iterable<Term> get terms => [ring];
}

final class SpaceTerms implements Vocabulary {
  const SpaceTerms();

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

final class RadiusTerms implements Vocabulary {
  const RadiusTerms();

  Term<Dimension> get control => const Term(Identifier('radius.control'));

  Term<Dimension> get surface => const Term(Identifier('radius.surface'));

  Term<Dimension> get field => const Term(Identifier('radius.field'));

  @override
  Iterable<Term> get terms => [control, surface, field];
}

final class SizeTerms implements Vocabulary {
  const SizeTerms();

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

final class StrokeTerms implements Vocabulary {
  const StrokeTerms();

  Term<Dimension> get width => const Term(Identifier('stroke.width'));

  Term<Dimension> get focusWidth => const Term(Identifier('stroke.focusWidth'));

  Term<StrokeStyle> get style => const Term(Identifier('stroke.style'));

  @override
  Iterable<Term> get terms => [width, focusWidth, style];
}

final class ShadowTerms implements Vocabulary {
  const ShadowTerms();

  Term<Shadow> get none => const Term(Identifier('shadow.none'));

  Term<Shadow> get raised => const Term(Identifier('shadow.raised'));

  Term<Shadow> get overlay => const Term(Identifier('shadow.overlay'));

  @override
  Iterable<Term> get terms => [none, raised, overlay];
}

final class OpacityTerms implements Vocabulary {
  const OpacityTerms();

  Term<double> get disabled => const Term(Identifier('opacity.disabled'));

  @override
  Iterable<Term> get terms => [disabled];
}

final class TypeTerms implements Vocabulary {
  const TypeTerms();

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

final class IconTerms implements Vocabulary {
  const IconTerms();

  Term<Identifier> get buttonLeading =>
      const Term(Identifier('icon.buttonLeading'));

  Term<Identifier> get fieldError => const Term(Identifier('icon.fieldError'));

  @override
  Iterable<Term> get terms => [buttonLeading, fieldError];
}

void main() {
  final diagnostics = design.validate();
  if (diagnostics.isNotEmpty) {
    for (final diagnostic in diagnostics) {
      print('${diagnostic.code}: ${diagnostic.message}');
    }
    throw StateError('The style design is invalid.');
  }

  final resolved = button.resolve(
    binding: dark,
    part: ButtonPart.icon,
    states: [state.hovered, state.focusVisible],
    axisValues: [buttonTone(.danger), buttonSize(.sm)],
  );

  print('button.fill=${formatColor(resolved.appearance.surface?.fill)}');
  print(
    'button.stroke=${formatColor(resolved.appearance.surface?.stroke?.color)}',
  );
  print(
    'button.strokeWidth='
    '${formatDimension(resolved.appearance.surface?.stroke?.width)}',
  );
  print('button.content=${formatColor(resolved.appearance.content?.color)}');
  print('button.icon=${resolved.appearance.content?.icon?.value}');
  print('button.label=${resolved.appearance.content?.text?.value}');
  print(
    'button.height=${formatDimension(resolved.appearance.metrics?.minHeight)}',
  );
  print(
    'button.iconWidth=${formatDimension(resolved.appearance.metrics?.width)}',
  );
}
