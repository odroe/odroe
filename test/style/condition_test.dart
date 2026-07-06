import 'package:odroe/style.dart';
import 'package:test/test.dart';

enum ButtonSize { sm, md }

enum ButtonTone { primary, danger }

void main() {
  test('creates typed axis conditions by calling an axis', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );

    final condition = tone(.danger);

    expect(condition.axis, same(tone));
    expect(condition.value, ButtonTone.danger);
  });

  test('exposes the core semantic state namespace', () {
    expect(state.hovered.id.value, 'state.hovered');
    expect(state.pressed.id.value, 'state.pressed');
    expect(state.focused.id.value, 'state.focused');
    expect(state.focusVisible.id.value, 'state.focusVisible');
    expect(state.disabled.id.value, 'state.disabled');
    expect(state.selected.id.value, 'state.selected');
    expect(state.checked.id.value, 'state.checked');
    expect(state.expanded.id.value, 'state.expanded');
    expect(state.loading.id.value, 'state.loading');
    expect(state.error.id.value, 'state.error');
  });

  test('creates cases with dot shorthand factories', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    const size = Axis<ButtonSize>(
      id: Identifier('button.size'),
      defaultValue: ButtonSize.md,
    );

    final danger = tone(.danger);
    final cases = <Case>[
      .when(danger, const Appearance()),
      .when(state.hovered, const Appearance()),
      .all([tone(.danger), size(.sm)], const Appearance()),
      .any([state.pressed, state.focusVisible], const Appearance()),
    ];

    expect(cases[0].when, same(danger));
    expect(cases[1].when, same(state.hovered));
    expect(
      cases[2].when,
      isA<AllCondition>()
          .having((condition) => condition.conditions, 'conditions', [
            isA<AxisCondition<ButtonTone>>()
                .having((condition) => condition.axis, 'axis', same(tone))
                .having(
                  (condition) => condition.value,
                  'value',
                  ButtonTone.danger,
                ),
            isA<AxisCondition<ButtonSize>>()
                .having((condition) => condition.axis, 'axis', same(size))
                .having((condition) => condition.value, 'value', ButtonSize.sm),
          ]),
    );
    expect(
      cases[3].when,
      isA<AnyCondition>().having(
        (condition) => condition.conditions,
        'conditions',
        [same(state.pressed), same(state.focusVisible)],
      ),
    );
  });

  test('copies compound condition inputs into immutable lists', () {
    final conditions = [state.hovered];

    final condition = Condition.all(conditions) as AllCondition;
    conditions.add(state.focusVisible);

    expect(condition.conditions, hasLength(1));
    expect(
      () => condition.conditions.add(state.disabled),
      throwsUnsupportedError,
    );
  });

  test('creates negated conditions', () {
    const condition = Condition.not(State(Identifier('state.disabled')));

    expect(
      condition,
      isA<NotCondition>().having(
        (condition) => (condition.condition as State).id.value,
        'state id',
        'state.disabled',
      ),
    );
  });
}
