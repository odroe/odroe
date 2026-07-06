import 'package:odroe/style.dart';
import 'package:test/test.dart';

void main() {
  test(
    'declares visual fragments with concrete values and term references',
    () {
      const actionFill = Term<ColorValue>(Identifier('color.action.fill'));
      const controlRadius = Term<Unit>(Identifier('radius.control'));

      final appearance = Appearance(
        surface: Surface(
          fill: AppearanceValue.term(actionFill),
          radius: AppearanceValue.term(controlRadius),
        ),
        content: const Content(
          color: AppearanceValue.literal(ColorValue.hex(0xffffffff)),
        ),
        metrics: const Metrics(
          padding: Insets.symmetric(
            x: AppearanceValue.literal(Unit.px(16)),
            y: AppearanceValue.literal(Unit.px(8)),
          ),
        ),
      );

      expect(appearance.surface?.fill?.term, same(actionFill));
      expect(appearance.surface?.radius?.term, same(controlRadius));
      expect(
        appearance.content?.color?.literal,
        const ColorValue.hex(0xffffffff),
      );
      expect(appearance.metrics?.padding?.left?.literal, const Unit.px(16));
    },
  );

  test('merges appearances by facet and property', () {
    const baseFill = AppearanceValue.literal(ColorValue.hex(0xff006adc));
    const nextFill = AppearanceValue.literal(ColorValue.hex(0xff004488));
    const radius = AppearanceValue.literal(Unit.px(8));
    const contentColor = AppearanceValue.literal(ColorValue.hex(0xffffffff));

    const base = Appearance(
      surface: Surface(fill: baseFill, radius: radius),
      content: Content(color: contentColor),
    );
    const later = Appearance(surface: Surface(fill: nextFill));

    final merged = base.merge(later);

    expect(merged.surface?.fill, same(nextFill));
    expect(merged.surface?.radius, same(radius));
    expect(merged.content?.color, same(contentColor));
  });

  test('merges metrics padding by side', () {
    const base = Metrics(
      padding: Insets.symmetric(
        x: AppearanceValue.literal(Unit.px(16)),
        y: AppearanceValue.literal(Unit.px(8)),
      ),
      gap: AppearanceValue.literal(Unit.px(4)),
    );
    const later = Metrics(
      padding: Insets.only(left: AppearanceValue.literal(Unit.px(20))),
    );

    final merged = base.merge(later);

    expect(merged.padding?.left?.literal, const Unit.px(20));
    expect(merged.padding?.right?.literal, const Unit.px(16));
    expect(merged.padding?.top?.literal, const Unit.px(8));
    expect(merged.gap?.literal, const Unit.px(4));
  });
}
