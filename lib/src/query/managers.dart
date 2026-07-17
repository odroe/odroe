import 'dart:async';

/// Unsubscribes a listener or background task.
typedef QueryDispose = void Function();

/// Runtime classification used by retry and timer defaults.
final class QueryEnvironment {
  const QueryEnvironment({this.isServer = false});

  /// Whether this client belongs to one server request.
  final bool isServer;
}

/// Mutable application-focus signal with no platform dependency.
final class QueryFocusManager {
  QueryFocusManager({bool focused = true}) : _focused = focused;

  bool _focused;
  final Set<void Function(bool)> _listeners = <void Function(bool)>{};

  bool get isFocused => _focused;

  set isFocused(bool value) {
    if (_focused == value) return;
    _focused = value;
    for (final listener in List<void Function(bool)>.of(_listeners)) {
      listener(value);
    }
  }

  QueryDispose subscribe(void Function(bool focused) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// Mutable connectivity signal wired by an application or platform adapter.
final class QueryOnlineManager {
  QueryOnlineManager({bool online = true}) : _online = online;

  bool _online;
  final Set<void Function(bool)> _listeners = <void Function(bool)>{};

  bool get isOnline => _online;

  set isOnline(bool value) {
    if (_online == value) return;
    _online = value;
    for (final listener in List<void Function(bool)>.of(_listeners)) {
      listener(value);
    }
  }

  QueryDispose subscribe(void Function(bool online) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// Clock and timer seam used by tests, servers, and alternative runtimes.
abstract interface class QueryScheduler {
  DateTime now();

  Timer timer(Duration duration, void Function() callback);
}

/// Default wall-clock scheduler.
final class SystemQueryScheduler implements QueryScheduler {
  const SystemQueryScheduler();

  @override
  DateTime now() => DateTime.now();

  @override
  Timer timer(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}
