import 'package:odroe/style.dart';
import 'package:test/test.dart';

void main() {
  test('creates pixel dimensions from const constructors', () {
    const dimension = Dimension.px(16);

    expect(dimension, isA<PixelDimension>());
    expect((dimension as PixelDimension).value, 16);
  });

  test('creates pixel dimensions from numeric shorthand', () {
    final dimension = 16.px;

    expect(dimension, const Dimension.px(16));
  });
}
