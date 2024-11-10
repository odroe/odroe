import 'subscriber.dart';

/// Types of events that can be tracked for debugging
enum EventType {
  /// When a property is accessed (get)
  trackGet,

  /// When property existence is checked
  trackHas,

  /// When iterating over properties
  trackIterate,

  /// When a property is set
  triggerSet,

  /// When an item is added
  triggerAdd,

  /// When an item is deleted
  triggerDelete,

  /// When collection is cleared
  triggerClear,
}

/// Base class containing extra information about debugger events
class DebuggerEventExtraInfo {
  /// Creates a new debugger event info object
  const DebuggerEventExtraInfo({
    required this.target,
    required this.type,
    required this.key,
    this.newValue,
    this.oldValue,
    this.oldTarget,
  });

  /// The target object being operated on
  final Object target;

  /// The type of event that occurred
  final EventType type;

  /// The property key involved in the event
  final dynamic key;

  /// The new value being set, if applicable
  final Object? newValue;

  /// The previous value, if applicable
  final Object? oldValue;

  /// The previous target object, if applicable
  final Object? oldTarget;
}

/// A debugger event that includes subscriber effect information
class DebuggerEvent extends DebuggerEventExtraInfo {
  /// Creates a new debugger event
  const DebuggerEvent({
    required this.effect,
    required super.target,
    required super.key,
    required super.type,
    super.newValue,
    super.oldValue,
    super.oldTarget,
  });

  /// The subscriber effect associated with this event
  final Subscriber effect;
}

/// Interface for debugger configuration options
abstract interface class DebuggerOptions {
  /// Callback triggered when a property is tracked
  void Function(DebuggerEvent event)? onTrack;

  /// Callback triggered when a property change occurs
  void Function(DebuggerEvent event)? onTrigger;
}
