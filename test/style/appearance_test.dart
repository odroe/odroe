import 'package:odroe/style.dart';
import 'package:test/test.dart';

void main() {
  test(
    'declares visual fragments with concrete values and term references',
    () {
      const actionFill = Term<Color>(Identifier('color.action.fill'));
      const controlRadius = Term<Dimension>(Identifier('radius.control'));

      final appearance = Appearance(
        surface: Surface(fill: .term(actionFill), radius: .term(controlRadius)),
        content: const Content(color: .literal(Color(0xffffffff))),
        metrics: Metrics(
          padding: Insets.symmetric(x: .literal(16.px), y: .literal(8.px)),
        ),
      );

      expect(
        appearance.surface?.fill,
        isA<TermProperty<Color>>().having(
          (property) => property.term,
          'term',
          same(actionFill),
        ),
      );
      expect(
        appearance.surface?.radius,
        isA<TermProperty<Dimension>>().having(
          (property) => property.term,
          'term',
          same(controlRadius),
        ),
      );
      expect(
        appearance.content?.color,
        isA<LiteralProperty<Color>>().having(
          (property) => property.value,
          'value',
          const Color(0xffffffff),
        ),
      );
      expect(
        appearance.metrics?.padding?.left,
        isA<LiteralProperty<Dimension>>().having(
          (property) => property.value,
          'value',
          const Dimension.px(16),
        ),
      );
    },
  );

  test('merges appearances by facet and property', () {
    const Property<Color> baseFill = .literal(Color(0xff006adc));
    const Property<Color> nextFill = .literal(Color(0xff004488));
    const Property<Dimension> radius = .literal(Dimension.px(8));
    const Property<Color> contentColor = .literal(Color(0xffffffff));

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
        x: .literal(Dimension.px(16)),
        y: .literal(Dimension.px(8)),
      ),
      gap: .literal(Dimension.px(4)),
    );
    const later = Metrics(
      padding: Insets.only(left: .literal(Dimension.px(20))),
    );

    final merged = base.merge(later);

    expect(
      merged.padding?.left,
      isA<LiteralProperty<Dimension>>().having(
        (property) => property.value,
        'value',
        const Dimension.px(20),
      ),
    );
    expect(
      merged.padding?.right,
      isA<LiteralProperty<Dimension>>().having(
        (property) => property.value,
        'value',
        const Dimension.px(16),
      ),
    );
    expect(
      merged.padding?.top,
      isA<LiteralProperty<Dimension>>().having(
        (property) => property.value,
        'value',
        const Dimension.px(8),
      ),
    );
    expect(
      merged.gap,
      isA<LiteralProperty<Dimension>>().having(
        (property) => property.value,
        'value',
        const Dimension.px(4),
      ),
    );
  });
}
