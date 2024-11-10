import 'subscriber.dart';

enum EventType {
  trackGet,
  trackHas,
  trackIterate,
  triggerSet,
  triggerAdd,
  triggerDelete,
  triggerClear,
}

class DebuggerEventExtraInfo {
  const DebuggerEventExtraInfo({
    required this.target,
    required this.type,
    required this.key,
    this.newValue,
    this.oldValue,
    this.oldTarget,
  });

  final Object target;
  final EventType type;
  final dynamic key;
  final Object? newValue;
  final Object? oldValue;
  final Object? oldTarget;
}

class DebuggerEvent extends DebuggerEventExtraInfo {
  const DebuggerEvent({
    required this.effect,
    required super.target,
    required super.key,
    required super.type,
    super.newValue,
    super.oldValue,
    super.oldTarget,
  });

  final Subscriber effect;
}

abstract interface class DebuggerOptions {
  void Function(DebuggerEvent event)? onTrack;
  void Function(DebuggerEvent event)? onTrigger;
}
