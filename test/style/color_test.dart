import 'package:odroe/style.dart';
import 'package:test/test.dart';

void main() {
  test('constructs colors from packed ARGB values', () {
    const color = Color(0xff42a5f5);

    expect(color.a, 1.0);
    expect(color.r, closeTo(0x42 / 255, 0.0000001));
    expect(color.g, closeTo(0xa5 / 255, 0.0000001));
    expect(color.b, closeTo(0xf5 / 255, 0.0000001));
    expect(color.toARGB32(), 0xff42a5f5);
  });

  test('uses the lower bits of integer constructors', () {
    expect(const Color(0x1ff42a5f5), const Color(0xff42a5f5));
    expect(
      const Color.fromARGB(0x1ff, 0x142, 0x1a5, 0x1f5),
      const Color(0xff42a5f5),
    );
  });

  test('constructs colors from ARGB and RGBO channels', () {
    expect(
      const Color.fromARGB(0xff, 0x42, 0xa5, 0xf5),
      const Color(0xff42a5f5),
    );
    expect(const Color.fromRGBO(0x42, 0xa5, 0xf5, 1), const Color(0xff42a5f5));
  });

  test('updates individual channels', () {
    final color = const Color(0xff42a5f5).withValues(alpha: 0.5, red: 1);

    expect(color.toARGB32(), 0x80ffa5f5);
  });

  test('clamps floating-point channels when converting to ARGB', () {
    const color = Color.from(alpha: 2, red: -1, green: 0.5, blue: 1.5);

    expect(color.toARGB32(), 0xff0080ff);
  });
}
