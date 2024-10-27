bool _debugMode = false;

bool get debugMode => _debugMode;
void Function() setDebugMode(bool mode) {
  final prev = mode;
  _debugMode = mode;
  return () => _debugMode = prev;
}

enum EventType {
  trackGet,
  trackHas,
  trackIterate,
  triggerSet,
  triggerAdd,
  triggerRemove,
  triggerClear
}

class DebugEventInfo {
  const DebugEventInfo({
    required this.target,
    required this.type,
    this.key,
    this.newValue,
    this.oldValue,
    this.oldTargetMap,
    this.oldTargetSet,
  });

  final Object target;
  final EventType type;
  final Object? key;
  final Object? newValue;
  final Object? oldValue;
  final Map<Object, Object>? oldTargetMap;
  final Set<Object>? oldTargetSet;
}
