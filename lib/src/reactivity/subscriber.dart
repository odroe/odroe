import 'corss_link.dart';

/// The currently active subscriber
Subscriber? _activeSub;

/// Getter for the currently active subscriber
Subscriber? get activeSub => _activeSub;

/// Sets the active subscriber and returns a function to restore the previous one
///
/// [sub] The subscriber to set as active
/// Returns a function that restores the previous active subscriber when called
void Function() setActiveSub(Subscriber? sub) {
  final prev = activeSub;
  _activeSub = sub;
  return () => _activeSub = prev;
}

/// A subscriber interface that can receive notifications and maintain dependencies
abstract interface class Subscriber {
  /// Internal flags for subscriber state
  abstract int flags;

  /// Reference to the next subscriber in a linked list
  Subscriber? next;

  /// Head of the dependencies linked list
  CrossLink? depsHead;

  /// Tail of the dependencies linked list
  CrossLink? depsTail;

  /// Notifies this subscriber of changes
  void notify();
}
