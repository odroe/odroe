import 'package:flutter/widgets.dart';

import 'alert.dart';
import 'colors.dart';
import 'provider.dart';

enum Breakpoint {
  none,
  sm,
  base,
  md,
  lg,
  xl,
  xl2,
  xl3,
  full,
}

class Rounded {
  const Rounded._(this._seed);

  final num _seed;

  double breakpoint(Breakpoint breakpoint) {
    return switch (breakpoint) {
      Breakpoint.none => 0,
      Breakpoint.sm => _seed * .125,
      Breakpoint.base => _seed * .25,
      Breakpoint.md => _seed * .375,
      Breakpoint.lg => _seed * .5,
      Breakpoint.xl => _seed * .75,
      Breakpoint.xl2 => _seed * 1.0,
      Breakpoint.xl3 => _seed * 1.5,
      Breakpoint.full => 99999,
    };
  }

  double operator [](Breakpoint breakpoint) => this.breakpoint(breakpoint);
}

class ThemeData {
  const ThemeData(
      {this.brightness = Brightness.light,
      required this.primary,
      required this.text,
      this.alert = AlertStyle.fallback,
      this.base = 16,
      required this.rounded});

  final int base;
  final Brightness brightness;
  final OdroeColor primary;
  final OdroeColor text;
  final AlertStyle alert;

  final Rounded rounded;

  static const ThemeData fallback = ThemeData(
    primary: Colors.green,
    text: Colors.black,
    rounded: Rounded._(16),
  );
}

class Theme extends Provider<ThemeData> {
  const Theme({super.key, required super.data, required super.child});

  static ThemeData of(BuildContext context) =>
      Provider.of<ThemeData>(context) ?? ThemeData.fallback;
}
