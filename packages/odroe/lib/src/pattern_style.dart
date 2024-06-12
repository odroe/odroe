import 'style_sheet.dart';

abstract class PatternStyle {
  Pattern get pattern;

  StyleSheet build(Iterable<Match> matches);
}
