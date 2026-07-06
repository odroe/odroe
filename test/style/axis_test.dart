import 'package:odroe/style.dart';
import 'package:test/test.dart';

enum ButtonTone { primary, danger }

void main() {
  test('compares equal axes independently of their generic annotation', () {
    const typed = Axis<ButtonTone>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );
    const widened = Axis<Object?>(
      id: Identifier('button.tone'),
      defaultValue: ButtonTone.primary,
    );

    expect(typed, widened);
    expect(widened, typed);
    expect({typed}.contains(widened), isTrue);
  });
}
