import 'package:flutter/widgets.dart';

import 'named_style.dart';
import 'pattern_style.dart';
import 'style_sheet.dart';
import 'style_sheet_utils.dart';

class Style extends StatelessWidget {
  const Style({this.pattern, this.named, required this.child, super.key});

  final Iterable<PatternStyle>? pattern;
  final Map<String, StyleSheet>? named;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pattern = [
      ...?_maybePattern(context),
      ...?this.pattern,
      ...?named?.entries.map(_resolveNamedStyle)
    ];
    if (pattern.isEmpty) return child;

    return _PatternStyleProvider(pattern: pattern, child: child);
  }

  static NamedStyle _resolveNamedStyle(MapEntry<String, StyleSheet> e) {
    return NamedStyle(e.key, e.value);
  }

  static Iterable<PatternStyle>? _maybePattern(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_PatternStyleProvider>()
        ?.pattern;
  }

  static StyleSheet? maybeOf(BuildContext context, String aspect) {
    final provides = _maybePattern(context);
    if (provides == null || provides.isEmpty) {
      return null;
    }

    StyleSheet? style;
    for (final PatternStyle(pattern: pattern, build: build) in provides) {
      final matches = pattern.allMatches(aspect);
      if (matches.isEmpty) continue;

      final effect = build(matches);
      style = style?.merge(effect) ?? effect;
    }

    return style;
  }
}

class _PatternStyleProvider extends InheritedWidget {
  const _PatternStyleProvider({required super.child, required this.pattern});

  final Iterable<PatternStyle> pattern;

  @override
  bool updateShouldNotify(covariant _PatternStyleProvider oldWidget) {
    return Object.hashAllUnordered(oldWidget.pattern) !=
        Object.hashAllUnordered(pattern);
  }
}
