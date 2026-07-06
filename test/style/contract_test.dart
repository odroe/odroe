import 'package:odroe/style.dart';
import 'package:test/test.dart';

enum ButtonPart { icon, label }

enum ButtonTone { primary, danger }

void main() {
  test('declares optional parts axes and states', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );

    final contract = Contract<ButtonPart>(
      parts: {ButtonPart.icon, ButtonPart.label},
      axes: [tone],
      states: {state.hovered, state.disabled},
    );

    expect(contract.parts, {ButtonPart.icon, ButtonPart.label});
    expect(contract.axes, [tone]);
    expect(contract.states, {state.hovered, state.disabled});
  });

  test('reports whether members are declared', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    const sameTone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    const otherTone = Axis<ButtonTone>(
      id: Identifier('button.intent'),
      defaultValue: ButtonTone.primary,
    );

    final contract = Contract<ButtonPart>(
      parts: {ButtonPart.icon},
      axes: [tone],
      states: {state.hovered},
    );

    expect(contract.allowsPart(ButtonPart.icon), isTrue);
    expect(contract.allowsPart(ButtonPart.label), isFalse);
    expect(contract.allowsAxis(sameTone), isTrue);
    expect(contract.allowsAxis(otherTone), isFalse);
    expect(
      contract.allowsState(const State(Identifier('state.hovered'))),
      isTrue,
    );
    expect(contract.allowsState(state.disabled), isFalse);
  });

  test('copies contract collections into immutable containers', () {
    const tone = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    final parts = {ButtonPart.icon};
    final axes = [tone];
    final states = {state.hovered};

    final contract = Contract<ButtonPart>(
      parts: parts,
      axes: axes,
      states: states,
    );
    parts.add(ButtonPart.label);
    axes.clear();
    states.add(state.disabled);

    expect(contract.parts, {ButtonPart.icon});
    expect(contract.axes, [tone]);
    expect(contract.states, {state.hovered});
    expect(() => contract.parts.add(ButtonPart.label), throwsUnsupportedError);
    expect(() => contract.axes.add(tone), throwsUnsupportedError);
    expect(() => contract.states.add(state.disabled), throwsUnsupportedError);
  });
}
