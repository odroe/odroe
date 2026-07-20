import 'dart:async';

import 'client.dart';
import 'managers.dart';
import 'mutation_state.dart';
import 'options.dart';

/// Why mutation cache subscribers were notified.
enum MutationCacheEventType {
  /// A mutation entered the cache.
  added,

  /// A mutation left the cache.
  removed,

  /// A mutation state changed.
  updated,

  /// An observer started watching a mutation.
  observerAdded,

  /// An observer stopped watching a mutation.
  observerRemoved,
}

/// One mutation cache change.
final class MutationCacheEvent {
  /// Creates a cache event for [mutation].
  const MutationCacheEvent(this.type, this.mutation);

  /// The kind of cache change.
  final MutationCacheEventType type;

  /// The mutation affected by the change.
  final Mutation<dynamic, dynamic, dynamic> mutation;
}

/// Handles successful mutations across a cache.
typedef GlobalMutationSuccess =
    FutureOr<void> Function(
      Object? data,
      Object? variables,
      Object? optimistic,
      Mutation<dynamic, dynamic, dynamic> mutation,
      MutationContext context,
    );

/// Handles failed mutations across a cache.
typedef GlobalMutationError =
    FutureOr<void> Function(
      Object error,
      StackTrace stackTrace,
      Object? variables,
      Object? optimistic,
      Mutation<dynamic, dynamic, dynamic> mutation,
      MutationContext context,
    );

/// Owns mutation executions, serial scopes, and persistence events.
final class MutationCache {
  /// Creates a mutation cache with optional global callbacks.
  MutationCache({this.onSuccess, this.onError});

  /// Callback invoked after any mutation succeeds.
  final GlobalMutationSuccess? onSuccess;

  /// Callback invoked after any mutation fails.
  final GlobalMutationError? onError;
  final Set<Mutation<dynamic, dynamic, dynamic>> _mutations =
      <Mutation<dynamic, dynamic, dynamic>>{};
  final Map<String, List<Mutation<dynamic, dynamic, dynamic>>> _scopes =
      <String, List<Mutation<dynamic, dynamic, dynamic>>>{};
  final Set<void Function(MutationCacheEvent)> _listeners =
      <void Function(MutationCacheEvent)>{};

  /// All mutations currently in the cache.
  Iterable<Mutation<dynamic, dynamic, dynamic>> get all => _mutations;

  /// Creates and stores a mutation execution.
  Mutation<TData, TVariables, TOptimistic>
  build<TData, TVariables, TOptimistic>(
    QueryClient client,
    MutationOptions<TData, TVariables, TOptimistic> options, {
    MutationState<TData, TVariables, TOptimistic>? state,
  }) {
    final mutation = Mutation<TData, TVariables, TOptimistic>(
      client: client,
      cache: this,
      options: options,
      state: state,
    );
    _mutations.add(mutation);
    final scope = options.scope;
    if (scope != null) {
      (_scopes[scope] ??= <Mutation<dynamic, dynamic, dynamic>>[]).add(
        mutation,
      );
    }
    notify(MutationCacheEvent(MutationCacheEventType.added, mutation));
    return mutation;
  }

  /// Whether [mutation] is first in its serial scope.
  bool canRun(Mutation<dynamic, dynamic, dynamic> mutation) {
    final scope = mutation.options.scope;
    if (scope == null) return true;
    for (final pending in _scopes[scope]!) {
      if (pending.state.isPending) return identical(pending, mutation);
    }
    return true;
  }

  /// Removes and destroys [mutation].
  void remove(Mutation<dynamic, dynamic, dynamic> mutation) {
    if (!_mutations.remove(mutation)) return;
    final scope = mutation.options.scope;
    if (scope != null) {
      final scoped = _scopes[scope]!;
      scoped.remove(mutation);
      if (scoped.isEmpty) _scopes.remove(scope);
    }
    mutation.destroy();
    notify(MutationCacheEvent(MutationCacheEventType.removed, mutation));
  }

  /// Sends [event] to current subscribers.
  void notify(MutationCacheEvent event) {
    for (final listener in List<void Function(MutationCacheEvent)>.of(
      _listeners,
    )) {
      listener(event);
    }
  }

  /// Subscribes to mutation cache events.
  QueryDispose subscribe(void Function(MutationCacheEvent event) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Waits until [mutation] can run under scope and network constraints.
  Future<void> waitUntilRunnable(
    QueryClient client,
    Mutation<dynamic, dynamic, dynamic> mutation,
  ) async {
    bool ready() =>
        canRun(mutation) &&
        (mutation.options.networkMode != QueryNetworkMode.online ||
            client.onlineManager.isOnline);
    if (ready()) return;
    final completer = Completer<void>();
    void check([Object? _]) {
      if (ready() && !completer.isCompleted) completer.complete();
    }

    final removeCache = subscribe((_) => check());
    final removeOnline = client.onlineManager.subscribe(check);
    try {
      await completer.future;
    } finally {
      removeCache();
      removeOnline();
    }
  }

  /// Continues all cached mutations paused by network or scope constraints.
  Future<void> resumePaused(QueryClient client) async {
    await Future.wait<void>(
      _mutations.where((mutation) => mutation.state.isPaused).map((
        mutation,
      ) async {
        try {
          await mutation.continueExecution();
        } on Object {
          // The mutation state retains the failure for its observer.
        }
      }),
    );
  }

  /// Removes every cached mutation.
  void clear() {
    while (_mutations.isNotEmpty) {
      remove(_mutations.first);
    }
  }
}

/// One concrete mutation execution.
final class Mutation<TData, TVariables, TOptimistic> {
  /// Creates one concrete mutation execution.
  Mutation({
    required this.client,
    required this.cache,
    required this.options,
    MutationState<TData, TVariables, TOptimistic>? state,
  }) : state = state ?? MutationState<TData, TVariables, TOptimistic>.idle() {
    _scheduleGc();
  }

  /// The client executing this mutation.
  final QueryClient client;

  /// The cache that owns this mutation.
  final MutationCache cache;

  /// The mutation definition.
  final MutationOptions<TData, TVariables, TOptimistic> options;

  /// The latest execution state.
  MutationState<TData, TVariables, TOptimistic> state;

  final Set<void Function(MutationState<TData, TVariables, TOptimistic>)>
  _observers = <void Function(MutationState<TData, TVariables, TOptimistic>)>{};
  Timer? _gcTimer;
  Future<TData>? _future;
  bool _destroyed = false;

  /// Starts execution or returns the active execution.
  Future<TData> execute(TVariables variables) {
    final active = _future;
    if (active != null) return active;
    final execution = _execute(variables, restored: state.isPending);
    _future = execution.whenComplete(() {
      _future = null;
      _scheduleGc();
    });
    return _future!;
  }

  /// Continues a restored paused mutation.
  Future<TData> continueExecution() {
    final variables = state.variables;
    if (variables == null && null is! TVariables) {
      return Future<TData>.error(
        StateError('A restored mutation requires serialized variables.'),
      );
    }
    return execute(variables as TVariables);
  }

  Future<TData> _execute(TVariables variables, {required bool restored}) async {
    final context = MutationContext(
      client: client,
      key: options.key,
      meta: options.meta,
    );
    TOptimistic? optimistic = state.optimistic;
    final paused =
        !cache.canRun(this) ||
        (options.networkMode == QueryNetworkMode.online &&
            !client.onlineManager.isOnline);
    if (!restored) {
      _setState(
        MutationState<TData, TVariables, TOptimistic>(
          status: MutationStatus.pending,
          data: null,
          error: null,
          errorStackTrace: null,
          failureCount: 0,
          failureReason: null,
          isPaused: paused,
          variables: variables,
          optimistic: null,
          submittedAt: client.scheduler.now(),
        ),
      );
      try {
        optimistic = await options.onMutate?.call(variables, context);
        if (optimistic != state.optimistic) {
          _setState(_copyState(optimistic: optimistic));
        }
      } on Object catch (error, stackTrace) {
        await _fail(
          error,
          stackTrace,
          variables,
          optimistic,
          1,
          context,
          notifyCallbacks: false,
        );
      }
    }

    var failureCount = state.failureCount;
    while (true) {
      if (!cache.canRun(this) ||
          (options.networkMode == QueryNetworkMode.online &&
              !client.onlineManager.isOnline)) {
        _setState(_copyState(isPaused: true));
        await cache.waitUntilRunnable(client, this);
      }
      if (state.isPaused) _setState(_copyState(isPaused: false));

      late final TData data;
      try {
        data = await options.mutation(variables, context);
      } on Object catch (error, stackTrace) {
        failureCount++;
        if (options.retry.shouldRetry(failureCount, error)) {
          _setState(
            _copyState(failureCount: failureCount, failureReason: error),
          );
          await Future<void>.delayed(
            options.retryDelay(failureCount - 1, error),
          );
          if (options.networkMode != QueryNetworkMode.always &&
              !client.onlineManager.isOnline) {
            _setState(_copyState(isPaused: true));
            await cache.waitUntilRunnable(client, this);
          }
          continue;
        }

        await _fail(
          error,
          stackTrace,
          variables,
          optimistic,
          failureCount,
          context,
        );
      }

      try {
        await cache.onSuccess?.call(data, variables, optimistic, this, context);
        await options.onSuccess?.call(data, variables, optimistic, context);
        await options.onSettled?.call(
          data,
          null,
          variables,
          optimistic,
          context,
        );
      } on Object catch (error, stackTrace) {
        await _fail(
          error,
          stackTrace,
          variables,
          optimistic,
          1,
          context,
          notifyCallbacks: false,
        );
      }

      _setState(
        MutationState<TData, TVariables, TOptimistic>(
          status: MutationStatus.success,
          data: data,
          error: null,
          errorStackTrace: null,
          failureCount: 0,
          failureReason: null,
          isPaused: false,
          variables: variables,
          optimistic: optimistic,
          submittedAt: state.submittedAt,
        ),
      );
      return data;
    }
  }

  Future<Never> _fail(
    Object error,
    StackTrace stackTrace,
    TVariables variables,
    TOptimistic? optimistic,
    int failureCount,
    MutationContext context, {
    bool notifyCallbacks = true,
  }) async {
    Object thrown = error;
    StackTrace thrownStackTrace = stackTrace;
    if (notifyCallbacks) {
      try {
        await cache.onError?.call(
          error,
          stackTrace,
          variables,
          optimistic,
          this,
          context,
        );
        await options.onError?.call(
          error,
          stackTrace,
          variables,
          optimistic,
          context,
        );
        await options.onSettled?.call(
          null,
          error,
          variables,
          optimistic,
          context,
        );
      } on Object catch (callbackError, callbackStackTrace) {
        thrown = callbackError;
        thrownStackTrace = callbackStackTrace;
      }
    }
    _setState(
      MutationState<TData, TVariables, TOptimistic>(
        status: MutationStatus.error,
        data: null,
        error: error,
        errorStackTrace: stackTrace,
        failureCount: failureCount,
        failureReason: error,
        isPaused: false,
        variables: variables,
        optimistic: optimistic,
        submittedAt: state.submittedAt,
      ),
    );
    Error.throwWithStackTrace(thrown, thrownStackTrace);
  }

  MutationState<TData, TVariables, TOptimistic> _copyState({
    bool? isPaused,
    int? failureCount,
    Object? failureReason = _mutationUnset,
    Object? optimistic = _mutationUnset,
  }) => MutationState<TData, TVariables, TOptimistic>(
    status: state.status,
    data: state.data,
    error: state.error,
    errorStackTrace: state.errorStackTrace,
    failureCount: failureCount ?? state.failureCount,
    failureReason: identical(failureReason, _mutationUnset)
        ? state.failureReason
        : failureReason,
    isPaused: isPaused ?? state.isPaused,
    variables: state.variables,
    optimistic: identical(optimistic, _mutationUnset)
        ? state.optimistic
        : optimistic as TOptimistic?,
    submittedAt: state.submittedAt,
  );

  /// Subscribes to execution state changes.
  QueryDispose subscribe(
    void Function(MutationState<TData, TVariables, TOptimistic> state) listener,
  ) {
    _gcTimer?.cancel();
    _observers.add(listener);
    cache.notify(
      MutationCacheEvent(MutationCacheEventType.observerAdded, this),
    );
    listener(state);
    return () {
      if (_observers.remove(listener)) {
        cache.notify(
          MutationCacheEvent(MutationCacheEventType.observerRemoved, this),
        );
        _scheduleGc();
      }
    };
  }

  void _setState(MutationState<TData, TVariables, TOptimistic> value) {
    if (_destroyed) return;
    state = value;
    for (final observer
        in List<
          void Function(MutationState<TData, TVariables, TOptimistic>)
        >.of(_observers)) {
      observer(value);
    }
    cache.notify(MutationCacheEvent(MutationCacheEventType.updated, this));
  }

  void _scheduleGc() {
    _gcTimer?.cancel();
    if (_destroyed || _observers.isNotEmpty || state.isPending) return;
    if (options.gcTime == Duration.zero) {
      scheduleMicrotask(() {
        if (_observers.isEmpty && !state.isPending) cache.remove(this);
      });
    } else {
      _gcTimer = client.scheduler.timer(options.gcTime, () {
        if (_observers.isEmpty && !state.isPending) cache.remove(this);
      });
    }
  }

  /// Stops timers and releases observers.
  void destroy() {
    _destroyed = true;
    _gcTimer?.cancel();
    _observers.clear();
  }
}

const Object _mutationUnset = Object();
