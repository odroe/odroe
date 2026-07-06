import 'package:odroe/style.dart';
import 'package:test/test.dart';

void main() {
  test(
    'declares visual fragments with concrete values and term references',
    () {
      const actionFill = Term<ColorValue>(Identifier('color.action.fill'));
      const controlRadius = Term<Unit>(Identifier('radius.control'));

      final appearance = Appearance(
        surface: Surface(fill: .term(actionFill), radius: .term(controlRadius)),
        content: const Content(color: .literal(ColorValue.hex(0xffffffff))),
        metrics: const Metrics(
          padding: Insets.symmetric(
            x: .literal(Unit.px(16)),
            y: .literal(Unit.px(8)),
          ),
        ),
      );

      expect(
        appearance.surface?.fill,
        isA<TermProperty<ColorValue>>().having(
          (property) => property.term,
          'term',
          same(actionFill),
        ),
      );
      expect(
        appearance.surface?.radius,
        isA<TermProperty<Unit>>().having(
          (property) => property.term,
          'term',
          same(controlRadius),
        ),
      );
      expect(
        appearance.content?.color,
        isA<LiteralProperty<ColorValue>>().having(
          (property) => property.value,
          'value',
          const ColorValue.hex(0xffffffff),
        ),
      );
      expect(
        appearance.metrics?.padding?.left,
        isA<LiteralProperty<Unit>>().having(
          (property) => property.value,
          'value',
          const Unit.px(16),
        ),
      );
    },
  );

  test('merges appearances by facet and property', () {
    const Property<ColorValue> baseFill = .literal(ColorValue.hex(0xff006adc));
    const Property<ColorValue> nextFill = .literal(ColorValue.hex(0xff004488));
    const Property<Unit> radius = .literal(Unit.px(8));
    const Property<ColorValue> contentColor = .literal(
      ColorValue.hex(0xffffffff),
    );

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
        x: .literal(Unit.px(16)),
        y: .literal(Unit.px(8)),
      ),
      gap: .literal(Unit.px(4)),
    );
    const later = Metrics(padding: Insets.only(left: .literal(Unit.px(20))));

    final merged = base.merge(later);

    expect(
      merged.padding?.left,
      isA<LiteralProperty<Unit>>().having(
        (property) => property.value,
        'value',
        const Unit.px(20),
      ),
    );
    expect(
      merged.padding?.right,
      isA<LiteralProperty<Unit>>().having(
        (property) => property.value,
        'value',
        const Unit.px(16),
      ),
    );
    expect(
      merged.padding?.top,
      isA<LiteralProperty<Unit>>().having(
        (property) => property.value,
        'value',
        const Unit.px(8),
      ),
    );
    expect(
      merged.gap,
      isA<LiteralProperty<Unit>>().having(
        (property) => property.value,
        'value',
        const Unit.px(4),
      ),
    );
  });
}
