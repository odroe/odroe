import 'package:flutter/rendering.dart';

EdgeInsets createEdgeInsets({
  Iterable<double>? basic,
  double? top,
  double? right,
  double? bottom,
  double? left,
}) {
  double generate(int index) {
    return switch (index) {
      0 => top ?? basic?.elementAtOrNull(0) ?? 0.0,
      1 => right ?? basic?.elementAtOrNull(1) ?? generate(0),
      2 => bottom ?? basic?.elementAtOrNull(2) ?? generate(0),
      3 => left ?? basic?.elementAtOrNull(3) ?? generate(1),
      _ => 0.0
    };
  }

  final [t, r, b, l] = List.generate(4, generate);
  return EdgeInsets.fromLTRB(l, t, r, b);
}
