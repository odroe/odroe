import 'package:odroe/style.dart';

enum ButtonPart { icon, label }

enum ButtonSize { sm, md }

enum ButtonTone { primary, danger }

const buttonSize = Axis<ButtonSize>(
  id: Identifier('button.size'),
  defaultValue: ButtonSize.md,
);
const buttonTone = Axis<ButtonTone>(
  id: Identifier('button.tone'),
  defaultValue: ButtonTone.primary,
);
const terms = AppTerms();

void main() {
  final light = Binding(Identifier('light'), [
    terms.color.action.fill(const Color(0xff0969da)),
    terms.color.action.fillHover(const Color(0xff0550ae)),
    terms.color.action.content(const Color(0xffffffff)),
    terms.color.danger.fill(const Color(0xffcf222e)),
    terms.color.danger.fillHover(const Color(0xffa40e26)),
    terms.color.danger.content(const Color(0xffffffff)),
    terms.radius.control(8.px),
    terms.space.controlX(16.px),
    terms.space.controlY(8.px),
    terms.space.controlSmX(12.px),
    terms.space.controlSmY(6.px),
    terms.size.icon(18.px),
    terms.size.iconSm(16.px),
    terms.size.controlHeight(40.px),
    terms.size.controlSmHeight(32.px),
    terms.type.buttonLabel(const Identifier('text.buttonLabel')),
    terms.type.buttonLabelSm(const Identifier('text.buttonLabelSm')),
    terms.icon.leading(const Identifier('icon.plus')),
  ]);
  final dark = Binding(Identifier('dark'), [
    terms.color.action.fill(const Color(0xff1f6feb)),
    terms.color.action.fillHover(const Color(0xff388bfd)),
    terms.color.action.content(const Color(0xffffffff)),
    terms.color.danger.fill(const Color(0xffda3633)),
    terms.color.danger.fillHover(const Color(0xffff7b72)),
    terms.color.danger.content(const Color(0xff0d1117)),
    terms.radius.control(8.px),
    terms.space.controlX(16.px),
    terms.space.controlY(8.px),
    terms.space.controlSmX(12.px),
    terms.space.controlSmY(6.px),
    terms.size.icon(18.px),
    terms.size.iconSm(16.px),
    terms.size.controlHeight(40.px),
    terms.size.controlSmHeight(32.px),
    terms.type.buttonLabel(const Identifier('text.buttonLabel')),
    terms.type.buttonLabelSm(const Identifier('text.buttonLabelSm')),
    terms.icon.leading(const Identifier('icon.plus')),
  ]);
  final button = buttonStyle();
  final design = Design(
    vocabulary: terms,
    bindings: [light, dark],
    styles: [button],
  );
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
    states: [state.hovered],
    axisValues: [buttonTone(.danger), buttonSize(.sm)],
  );

  print('button.fill=${formatColor(resolved.appearance.surface?.fill)}');
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

Style<ButtonPart> buttonStyle() {
  return Style<ButtonPart>(
    id: Identifier('button'),
    contract: Contract<ButtonPart>(
      parts: {ButtonPart.icon, ButtonPart.label},
      axes: [buttonTone, buttonSize],
      states: {state.hovered},
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
        minHeight: .term(terms.size.controlHeight),
      ),
    ),
    parts: {
      ButtonPart.icon: Appearance(
        content: Content(icon: .term(terms.icon.leading)),
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
        buttonTone(.danger),
        Appearance(
          surface: Surface(fill: .term(terms.color.danger.fill)),
          content: Content(color: .term(terms.color.danger.content)),
        ),
      ),
      .all(
        [buttonTone(.danger), state.hovered],
        Appearance(surface: Surface(fill: .term(terms.color.danger.fillHover))),
      ),
    ],
  );
}

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

final class AppTerms implements Vocabulary {
  const AppTerms();

  ColorTerms get color => const ColorTerms();

  IconTerms get icon => const IconTerms();

  RadiusTerms get radius => const RadiusTerms();

  SizeTerms get size => const SizeTerms();

  SpaceTerms get space => const SpaceTerms();

  TypeTerms get type => const TypeTerms();

  @override
  Iterable<Term> get terms => [
    ...color.terms,
    ...icon.terms,
    ...radius.terms,
    ...size.terms,
    ...space.terms,
    ...type.terms,
  ];
}

final class ColorTerms implements Vocabulary {
  const ColorTerms();

  ActionColorTerms get action => const ActionColorTerms();

  DangerColorTerms get danger => const DangerColorTerms();

  @override
  Iterable<Term> get terms => [...action.terms, ...danger.terms];
}

final class ActionColorTerms implements Vocabulary {
  const ActionColorTerms();

  Term<Color> get fill => const Term(Identifier('color.action.fill'));

  Term<Color> get fillHover => const Term(Identifier('color.action.fillHover'));

  Term<Color> get content => const Term(Identifier('color.action.content'));

  @override
  Iterable<Term> get terms => [fill, fillHover, content];
}

final class DangerColorTerms implements Vocabulary {
  const DangerColorTerms();

  Term<Color> get fill => const Term(Identifier('color.danger.fill'));

  Term<Color> get fillHover => const Term(Identifier('color.danger.fillHover'));

  Term<Color> get content => const Term(Identifier('color.danger.content'));

  @override
  Iterable<Term> get terms => [fill, fillHover, content];
}

final class IconTerms implements Vocabulary {
  const IconTerms();

  Term<Identifier> get leading => const Term(Identifier('icon.leading'));

  @override
  Iterable<Term> get terms => [leading];
}

final class RadiusTerms implements Vocabulary {
  const RadiusTerms();

  Term<Dimension> get control => const Term(Identifier('radius.control'));

  @override
  Iterable<Term> get terms => [control];
}

final class SizeTerms implements Vocabulary {
  const SizeTerms();

  Term<Dimension> get icon => const Term(Identifier('size.icon'));

  Term<Dimension> get iconSm => const Term(Identifier('size.iconSm'));

  Term<Dimension> get controlHeight =>
      const Term(Identifier('size.controlHeight'));

  Term<Dimension> get controlSmHeight =>
      const Term(Identifier('size.controlSmHeight'));

  @override
  Iterable<Term> get terms => [icon, iconSm, controlHeight, controlSmHeight];
}

final class SpaceTerms implements Vocabulary {
  const SpaceTerms();

  Term<Dimension> get controlX => const Term(Identifier('space.controlX'));

  Term<Dimension> get controlY => const Term(Identifier('space.controlY'));

  Term<Dimension> get controlSmX => const Term(Identifier('space.controlSmX'));

  Term<Dimension> get controlSmY => const Term(Identifier('space.controlSmY'));

  @override
  Iterable<Term> get terms => [controlX, controlY, controlSmX, controlSmY];
}

final class TypeTerms implements Vocabulary {
  const TypeTerms();

  Term<Identifier> get buttonLabel =>
      const Term(Identifier('type.buttonLabel'));

  Term<Identifier> get buttonLabelSm =>
      const Term(Identifier('type.buttonLabelSm'));

  @override
  Iterable<Term> get terms => [buttonLabel, buttonLabelSm];
}
