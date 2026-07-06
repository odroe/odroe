import 'package:odroe/style.dart';
import 'package:test/test.dart';

enum ButtonPart { icon, label }

enum ButtonTone { primary, danger }

void main() {
  test('declares a style with contract root parts and cases', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    final contract = Contract<ButtonPart>(
      parts: {ButtonPart.icon, ButtonPart.label},
      axes: [tone],
      states: {state.hovered},
    );
    const root = Appearance(
      surface: Surface(fill: .literal(Color(0xff006adc))),
    );
    const icon = Appearance(
      metrics: Metrics(width: .literal(Dimension.px(16))),
    );
    const hover = Appearance(
      surface: Surface(fill: .literal(Color(0xff0055aa))),
    );

    final style = Style<ButtonPart>(
      id: Identifier('button'),
      contract: contract,
      root: root,
      parts: {ButtonPart.icon: icon},
      cases: [.when(state.hovered, hover), .when(tone(.danger), hover)],
    );

    expect(style.id.value, 'button');
    expect(style.contract, same(contract));
    expect(style.root, same(root));
    expect(style.parts, {ButtonPart.icon: icon});
    expect(style.cases, hasLength(2));
  });

  test('declares a style without a contract', () {
    final style = Style<Object?>(
      id: Identifier('surface'),
      root: const Appearance(),
    );

    expect(style.contract, isNull);
    expect(style.parts, isEmpty);
    expect(style.cases, isEmpty);
  });

  test('copies style parts and cases into immutable containers', () {
    final parts = {ButtonPart.icon: const Appearance()};
    final cases = [Case.when(state.hovered, const Appearance())];

    final style = Style<ButtonPart>(
      id: Identifier('button'),
      root: const Appearance(),
      parts: parts,
      cases: cases,
    );
    parts[ButtonPart.label] = const Appearance();
    cases.clear();

    expect(style.parts, hasLength(1));
    expect(style.cases, hasLength(1));
    expect(
      () => style.parts[ButtonPart.label] = const Appearance(),
      throwsUnsupportedError,
    );
    expect(
      () => style.cases.add(Case.when(state.disabled, const Appearance())),
      throwsUnsupportedError,
    );
  });
}
