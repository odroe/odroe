library;

import 'package:flutter/widgets.dart';

import 'src/element.dart';
import 'src/runes/context.dart';

/// Class-style Widget when Setup runes base widget.
///
/// ```dart
/// class Counter extends SetupWidget {
///   const Counter({super.key});
///
///   Widget build(BuildContext context) {
///     final count = $state(0);
///
///     void increment() => count.set(count.get() + 1);
///
///     return TextButton(
///       onPressed: increment,
///       child: Text('Count: ${count.get()}),
///     );
///   }
/// }
/// ```
abstract class SetupWidget extends Widget {
  const SetupWidget({super.key});

  @override
  SetupElement createElement() => SetupElement(this, () => build($context()));

  @protected
  Widget build(BuildContext context);
}
