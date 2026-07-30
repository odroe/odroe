import 'dart:async';

import 'http.dart';

/// Handles one request with adapter-owned invocation state.
typedef ServerInvocationHandler =
    Future<ServerResponse> Function(
      ServerRequest request,
      ServerInvocation invocation,
    );

/// Observes an invocation failure that cannot be returned in the response.
typedef ServerInvocationErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Adapter-owned state scoped to one server request.
final class ServerInvocation {
  /// Creates an invocation from opaque platform [bindings].
  ///
  /// [onError] observes cleanup failures when no host lifetime is available and
  /// synchronous failures from a host [waitUntil] callback.
  ServerInvocation({
    this.bindings,
    void Function(Future<void> task)? waitUntil,
    ServerInvocationErrorHandler? onError,
  }) : _waitUntil = waitUntil,
       _onError = onError ?? _defaultServerInvocationError,
       _tasks = <Future<_InvocationFailure?>>[];

  ServerInvocation._empty()
    : bindings = null,
      _waitUntil = null,
      _onError = _defaultServerInvocationError,
      _tasks = null;

  /// Sentinel for manually created request contexts without an invocation.
  ///
  /// It cannot handle requests or keep background work alive.
  static final ServerInvocation empty = ServerInvocation._empty();

  /// Opaque bindings supplied by the hosting adapter.
  final Object? bindings;

  final void Function(Future<void> task)? _waitUntil;
  final ServerInvocationErrorHandler _onError;
  final List<Future<_InvocationFailure?>>? _tasks;
  bool _started = false;
  bool _finishing = false;
  bool _closed = false;
  bool _hasUnhostedTask = false;

  /// Whether the adapter can extend the request lifetime.
  bool get supportsWaitUntil => _waitUntil != null;

  /// Returns the platform bindings when they have type [T].
  T? maybeBindings<T extends Object>() {
    final value = bindings;
    return value is T ? value : null;
  }

  /// Returns the platform bindings as [T] or throws when unavailable.
  T requireBindings<T extends Object>() {
    final value = maybeBindings<T>();
    if (value == null) {
      throw StateError('Missing server invocation bindings: $T.');
    }
    return value;
  }

  /// Keeps [task] alive without delaying the response.
  ///
  /// Tasks may register more tasks before they complete. Invocation-aware
  /// handlers wait for the complete task tree before disposing their modules.
  void waitUntil(Future<void> task) {
    final tasks = _tasks;
    if (tasks == null) {
      _observeTask(task);
      throw StateError(
        'ServerInvocation.empty cannot keep background work alive.',
      );
    }
    if (_closed) {
      throw StateError('The server invocation is already complete.');
    }
    tasks.add(
      task.then<_InvocationFailure?>(
        (_) => null,
        onError: (Object error, StackTrace stackTrace) =>
            _InvocationFailure(error, stackTrace),
      ),
    );
    if (!_registerWithHost(task, backgroundTask: true)) {
      _hasUnhostedTask = true;
    }
  }

  bool _registerWithHost(Future<void> task, {required bool backgroundTask}) {
    final waitUntil = _waitUntil;
    if (waitUntil == null) return false;
    try {
      waitUntil(task);
      return true;
    } on Object catch (error, stackTrace) {
      if (backgroundTask) _hasUnhostedTask = true;
      _report(error, stackTrace);
      return false;
    }
  }

  void _observeTask(Future<void> task) {
    unawaited(
      task.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _report(error, stackTrace);
        },
      ),
    );
  }

  void _report(Object error, StackTrace stackTrace) {
    try {
      _onError(error, stackTrace);
    } on Object catch (reportError, reportStackTrace) {
      _defaultServerInvocationError(reportError, reportStackTrace);
    }
  }
}

/// Marks [invocation] as owned by one request.
void startServerInvocation(ServerInvocation invocation) {
  if (identical(invocation, ServerInvocation.empty)) {
    throw StateError('ServerInvocation.empty cannot handle a request.');
  }
  if (invocation._started) {
    throw StateError('A server invocation can handle only one request.');
  }
  invocation._started = true;
}

/// Schedules invocation cleanup after its response and background work finish.
void finishServerInvocation(
  ServerInvocation invocation, {
  required Future<void> responseDone,
  required FutureOr<void> Function() dispose,
}) {
  if (identical(invocation, ServerInvocation.empty)) {
    throw StateError('ServerInvocation.empty cannot finish a request.');
  }
  if (invocation._finishing) {
    throw StateError('The server invocation is already finishing.');
  }
  invocation._finishing = true;
  final cleanup = _finishServerInvocation(
    invocation,
    responseDone: responseDone,
    dispose: dispose,
  );
  if (!invocation._registerWithHost(cleanup, backgroundTask: false)) {
    invocation._observeTask(cleanup);
  }
}

Future<void> _finishServerInvocation(
  ServerInvocation invocation, {
  required Future<void> responseDone,
  required FutureOr<void> Function() dispose,
}) async {
  _InvocationFailure? firstFailure;
  try {
    await responseDone;
    final tasks = invocation._tasks;
    if (tasks != null) {
      var index = 0;
      while (index < tasks.length) {
        final end = tasks.length;
        final failures = await Future.wait<_InvocationFailure?>(
          tasks.getRange(index, end),
        );
        index = end;
        firstFailure ??= failures.whereType<_InvocationFailure>().firstOrNull;
      }
    }
  } finally {
    invocation._closed = true;
    try {
      await dispose();
    } on Object catch (error, stackTrace) {
      if (firstFailure != null &&
          (invocation._waitUntil == null || invocation._hasUnhostedTask)) {
        invocation._report(firstFailure.error, firstFailure.stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
  if (firstFailure case final failure?
      when invocation._waitUntil == null || invocation._hasUnhostedTask) {
    Error.throwWithStackTrace(failure.error, failure.stackTrace);
  }
}

final class _InvocationFailure {
  const _InvocationFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

void _defaultServerInvocationError(Object error, StackTrace stackTrace) {
  Zone.current.print('Server invocation error: $error\n$stackTrace');
}
