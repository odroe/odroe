import 'package:meta/meta.dart';

import 'corss_link.dart';
import 'debugger.dart';

/// The currently active subscriber
Subscriber? _activeSub;

/// Getter for the currently active subscriber
Subscriber? get activeSub => _activeSub;

/// Sets the active subscriber and returns a function to restore the previous one
///
/// [sub] The subscriber to set as active
/// Returns a function that restores the previous active subscriber when called
void Function() setActiveSub(Subscriber sub) {
  final prev = activeSub;
  _activeSub = sub;
  return () => _activeSub = prev;
}

/// A subscriber interface that can receive notifications and maintain dependencies
abstract interface class Subscriber implements DebuggerOptions {
  /// Internal flags for subscriber state
  @internal
  abstract int flags;

  /// Reference to the next subscriber in a linked list
  @internal
  Subscriber? next;

  /// Head of the dependencies linked list
  @internal
  CrossLink? depsHead;

  /// Tail of the dependencies linked list
  @internal
  CrossLink? depsTail;

  /// Notifies this subscriber of changes
  @internal
  void notify();
}
