import 'package:flutter/widgets.dart';
import 'package:odroe/src/runes/context.dart';

/// Creates a [NavigatorState] rune.
///
/// `Navigator.of` is a commonly used content, especially when we want to
/// jump to a page.
///
/// ```dart
/// Widget example() => setup(() {
///   final context = $context;
///   final navigator = Navigator.of(context);
///
///   ...
/// });
/// ```
///
/// equivalent:
///
/// ```dart
/// Widget example() => setup(() {
///   final navigator = $navigator();
///
///   ...
/// });
/// ```
NavigatorState $navigator({bool root = false}) =>
    Navigator.of($context(), rootNavigator: root);
