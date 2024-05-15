import 'dart:ui' show Color;

export 'dart:ui' show Color, Brightness;

class OdroeColor extends Color {
  const OdroeColor(super.value, [this.onColor = const Color(0xffffffff)]);

  final Color onColor;
}

final class Colors {
  Colors._();

  static const white = OdroeColor(0xffffffff, Color(0xff000000));
  static const black = OdroeColor(0xff000000, Color(0xffffffff));
  static const green = OdroeColor(0xff16a34a);
}
