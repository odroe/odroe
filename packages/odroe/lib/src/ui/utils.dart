import 'colors.dart';

Color mixBlackColor(Color color, double percentage) {
  assert(percentage > 0.0 && percentage < 1.0);

  final r = (color.red - (color.red * percentage)).toInt();
  final g = (color.green - (color.green * percentage)).toInt();
  final b = (color.blue - (color.blue * percentage)).toInt();

  return Color.fromARGB(color.alpha, r, g, b);
}
