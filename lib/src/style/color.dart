/// A platform-neutral color value.
///
/// The default constructor accepts the same `0xAARRGGBB` packed integer shape
/// used by `dart:ui.Color`, without depending on Flutter's `dart:ui` library.
/// Channels are stored as floating-point components so declarations can keep
/// their authored values and convert back to an ARGB integer when needed.
///
/// ```dart
/// const blue = Color(0xff42a5f5);
/// const sameBlue = Color.fromARGB(0xff, 0x42, 0xa5, 0xf5);
/// ```
final class Color {
  /// Creates an sRGB color from the lower 32 bits of [value].
  ///
  /// The bits are interpreted as `0xAARRGGBB`: alpha in bits 24-31, red in
  /// bits 16-23, green in bits 8-15, and blue in bits 0-7.
  const Color(int value)
    : this._fromARGB(
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      );

  /// Creates a color from floating-point channel values.
  ///
  /// The conventional range for each channel is `0.0` to `1.0`. Values outside
  /// that range are preserved in the declaration and clamped only when
  /// converted with [toARGB32].
  const Color.from({
    required double alpha,
    required double red,
    required double green,
    required double blue,
  }) : a = alpha,
       r = red,
       g = green,
       b = blue;

  /// Creates an sRGB color from integer alpha, red, green, and blue channels.
  ///
  /// Only the lower 8 bits of each channel are used, matching
  /// `dart:ui.Color.fromARGB`.
  const Color.fromARGB(int a, int r, int g, int b) : this._fromARGB(a, r, g, b);

  /// Creates a color from red, green, blue, and opacity channels.
  ///
  /// Only the lower 8 bits of the red, green, and blue channels are used.
  /// The conventional range for [opacity] is `0.0` to `1.0`.
  const Color.fromRGBO(int r, int g, int b, double opacity)
    : a = opacity,
      r = (r & 0xff) / 255,
      g = (g & 0xff) / 255,
      b = (b & 0xff) / 255;

  const Color._fromARGB(int alpha, int red, int green, int blue)
    : this._fromRGBO(red, green, blue, (alpha & 0xff) / 255);

  const Color._fromRGBO(int red, int green, int blue, double opacity)
    : a = opacity,
      r = (red & 0xff) / 255,
      g = (green & 0xff) / 255,
      b = (blue & 0xff) / 255;

  /// The alpha channel as a floating-point component.
  final double a;

  /// The red channel as a floating-point component.
  final double r;

  /// The green channel as a floating-point component.
  final double g;

  /// The blue channel as a floating-point component.
  final double b;

  /// Returns a copy with the provided channels replaced.
  Color withValues({double? alpha, double? red, double? green, double? blue}) {
    return Color.from(
      alpha: alpha ?? a,
      red: red ?? r,
      green: green ?? g,
      blue: blue ?? b,
    );
  }

  /// Returns this color as a packed `0xAARRGGBB` integer.
  ///
  /// Channel values are rounded to the nearest 8-bit integer and clamped to the
  /// range `0..255`.
  int toARGB32() {
    return _floatToInt8(a) << 24 |
        _floatToInt8(r) << 16 |
        _floatToInt8(g) << 8 |
        _floatToInt8(b);
  }

  static int _floatToInt8(double value) {
    final scaled = (value * 255.0).round();

    if (scaled < 0) {
      return 0;
    }
    if (scaled > 255) {
      return 255;
    }
    return scaled;
  }

  @override
  bool operator ==(Object other) {
    return other is Color &&
        other.a == a &&
        other.r == r &&
        other.g == g &&
        other.b == b;
  }

  @override
  int get hashCode => Object.hash(a, r, g, b);

  @override
  String toString() {
    return 'Color('
        'alpha: ${a.toStringAsFixed(4)}, '
        'red: ${r.toStringAsFixed(4)}, '
        'green: ${g.toStringAsFixed(4)}, '
        'blue: ${b.toStringAsFixed(4)}'
        ')';
  }
}
