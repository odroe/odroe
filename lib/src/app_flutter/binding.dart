import 'package:flutter/widgets.dart';

import '../app/binding.dart';
import '../app/context.dart';

/// A Flutter-specific module contribution.
abstract class FlutterBinding implements ModuleBinding {
  /// Creates a Flutter binding.
  const FlutterBinding();

  /// Wraps [child] with the widgets contributed by this binding.
  Widget wrap(AppContext context, Widget child);

  /// Receives Flutter application lifecycle changes.
  void didChangeAppLifecycleState(
    AppContext context,
    AppLifecycleState state,
  ) {}
}
