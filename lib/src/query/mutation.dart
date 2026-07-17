// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'client.dart';
import 'key.dart';
import 'managers.dart';
import 'options.dart';

enum MutationStatus { idle, pending, success, error }

/// Immutable state of one mutation execution.
final class MutationState<TData, TVariables, TOptimistic> {
  const MutationState({
    required this.status,
    required this.data,
    required this.error,
    required this.errorStackTrace,
    required this.failureCount,
    required this.failureReason,
    required this.isPaused,
    required this.variables,
    required this.optimistic,
    required this.submittedAt,
  });

  factory MutationState.idle() => MutationState<TData, TVariables, TOptimistic>(
    status: MutationStatus.idle,
    data: null,
    error: null,
    errorStackTrace: null,
    failureCount: 0,
    failureReason: null,
    isPaused: false,
    variables: null,
    optimistic: null,
    submittedAt: null,
  );

  final MutationStatus status;
  final TData? data;
  final Object? error;
  final StackTrace? errorStackTrace;
  final int failureCount;
  final Object? failureReason;
  final bool isPaused;
  final TVariables? variables;
  final TOptimistic? optimistic;
  final DateTime? submittedAt;

  bool get isIdle => status == MutationStatus.idle;
  bool get isPending => status == MutationStatus.pending;
  bool get isSuccess => status == MutationStatus.success;
  bool get isError => status == MutationStatus.error;
}

/// Input shared by mutation lifecycle callbacks.
final class MutationContext {
  const MutationContext({
    required this.client,
    required this.key,
    required this.meta,
  });

  final QueryClient client;
  final QueryKey? key;
  final Map<String, Object?> meta;
}

typedef MutationFunction<TData, TVariables> =
    FutureOr<TData> Function(TVariables variables, MutationContext context);
typedef MutationOnMutate<TVariables, TOptimistic> =
    FutureOr<TOptimistic> Function(
      TVariables variables,
      MutationContext context,
    );
typedef MutationOnSuccess<TData, TVariables, TOptimistic> =
    FutureOr<void> Function(
      TData data,
      TVariables variables,
      TOptimistic? optimistic,
      MutationContext context,
    );
typedef MutationOnError<TVariables, TOptimistic> =
    FutureOr<void> Function(
      Object error,
      StackTrace stackTrace,
      TVariables variables,
      TOptimistic? optimistic,
      MutationContext context,
    );
typedef MutationOnSettled<TData, TVariables, TOptimistic> =
    FutureOr<void> Function(
      TData? data,
      Object? error,
      TVariables variables,
      TOptimistic? optimistic,
      MutationContext context,
    );

/// Strongly typed definition for one mutation kind.
final class MutationOptions<TData, TVariables, TOptimistic> {
  const MutationOptions({
    required this.mutation,
    this.key,
    this.scope,
    this.retry = const QueryRetry.never(),
    this.retryDelay = defaultQueryRetryDelay,
    this.networkMode = QueryNetworkMode.online,
    this.gcTime = const Duration(minutes: 5),
    this.meta = const <String, Object?>{},
    this.onMutate,
    this.onSuccess,
    this.onError,
    this.onSettled,
  });

  final MutationFunction<TData, TVariables> mutation;
  final QueryKey? key;

  /// Mutations in the same non-null scope execute serially.
  final String? scope;
  final QueryRetry retry;
  final Duration Function(int failureCount, Object error) retryDelay;
  final QueryNetworkMode networkMode;
  final Duration gcTime;
  final Map<String, Object?> meta;
  final MutationOnMutate<TVariables, TOptimistic>? onMutate;
  final MutationOnSuccess<TData, TVariables, TOptimistic>? onSuccess;
  final MutationOnError<TVariables, TOptimistic>? onError;
  final MutationOnSettled<TData, TVariables, TOptimistic>? onSettled;
}

enum MutationCacheEventType {
  added,
  removed,
  updated,
  observerAdded,
  observerRemoved,
}

final class MutationCacheEvent {
  const MutationCacheEvent(this.type, this.mutation);

  final MutationCacheEventType type;
  final Mutation<dynamic, dynamic, dynamic> mutation;
}

typedef GlobalMutationSuccess =
    FutureOr<void> Function(
      Object? data,
      Object? variables,
      Object? optimistic,
      Mutation<dynamic, dynamic, dynamic> mutation,
      MutationContext context,
    );
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
  MutationCache({this.onSuccess, this.onError});

  final GlobalMutationSuccess? onSuccess;
  final GlobalMutationError? onError;
  final Set<Mutation<dynamic, dynamic, dynamic>> _mutations =
      <Mutation<dynamic, dynamic, dynamic>>{};
  final Map<String, List<Mutation<dynamic, dynamic, dynamic>>> _scopes =
      <String, List<Mutation<dynamic, dynamic, dynamic>>>{};
  final Set<void Function(MutationCacheEvent)> _listeners =
      <void Function(MutationCacheEvent)>{};
  int _nextId = 0;

  List<Mutation<dynamic, dynamic, dynamic>> get all =>
      List<Mutation<dynamic, dynamic, dynamic>>.unmodifiable(_mutations);

  Mutation<TData, TVariables, TOptimistic>
  build<TData, TVariables, TOptimistic>(
    QueryClient client,
    MutationOptions<TData, TVariables, TOptimistic> options, {
    MutationState<TData, TVariables, TOptimistic>? state,
  }) {
    final mutation = Mutation<TData, TVariables, TOptimistic>(
      id: ++_nextId,
      client: client,
      cache: this,
      options: options,
      state: state,
    );
    _mutations.add(mutation);
    final scope = options.scope;
    if (scope != null) {
      final mutations = _scopes.putIfAbsent(
        scope,
        () => <Mutation<dynamic, dynamic, dynamic>>[],
      );
      mutations.add(mutation);
    }
    notify(MutationCacheEvent(MutationCacheEventType.added, mutation));
    return mutation;
  }

  bool canRun(Mutation<dynamic, dynamic, dynamic> mutation) {
    final scope = mutation.options.scope;
    if (scope == null) return true;
    final pending = _scopes[scope]?.where((item) => item.state.isPending);
    return pending == null ||
        pending.isEmpty ||
        identical(pending.first, mutation);
  }

  void remove(Mutation<dynamic, dynamic, dynamic> mutation) {
    if (!_mutations.remove(mutation)) return;
    final scope = mutation.options.scope;
    if (scope != null) {
      final scoped = _scopes[scope];
      scoped?.remove(mutation);
      if (scoped?.isEmpty == true) _scopes.remove(scope);
    }
    mutation.destroy();
    notify(MutationCacheEvent(MutationCacheEventType.removed, mutation));
  }

  void notify(MutationCacheEvent event) {
    for (final listener in List<void Function(MutationCacheEvent)>.of(
      _listeners,
    )) {
      listener(event);
    }
  }

  QueryDispose subscribe(void Function(MutationCacheEvent event) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

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

  Future<void> resumePaused(QueryClient client) async {
    final paused = _mutations.where((mutation) => mutation.state.isPaused);
    await Future.wait<void>(
      paused.map((mutation) async {
        try {
          await mutation.continueExecution();
        } on Object {
          // Each mutation state preserves its own failure.
        }
      }),
    );
  }

  void clear() {
    for (final mutation in List<Mutation<dynamic, dynamic, dynamic>>.of(
      _mutations,
    )) {
      remove(mutation);
    }
  }
}

/// One concrete mutation execution.
final class Mutation<TData, TVariables, TOptimistic> {
  Mutation({
    required this.id,
    required this.client,
    required this.cache,
    required this.options,
    MutationState<TData, TVariables, TOptimistic>? state,
  }) : state = state ?? MutationState<TData, TVariables, TOptimistic>.idle() {
    _scheduleGc();
  }

  final int id;
  final QueryClient client;
  final MutationCache cache;
  final MutationOptions<TData, TVariables, TOptimistic> options;
  MutationState<TData, TVariables, TOptimistic> state;

  final Set<void Function(MutationState<TData, TVariables, TOptimistic>)>
  _observers = <void Function(MutationState<TData, TVariables, TOptimistic>)>{};
  Timer? _gcTimer;
  Future<TData>? _future;
  bool _destroyed = false;

  Future<TData> execute(TVariables variables) {
    final active = _future;
    if (active != null) return active;
    _future = _execute(variables, restored: state.isPending).whenComplete(() {
      _future = null;
      _scheduleGc();
      cache.notify(MutationCacheEvent(MutationCacheEventType.updated, this));
    });
    return _future!;
  }

  Future<TData> continueExecution() {
    final variables = state.variables;
    if (variables == null) {
      return Future<TData>.error(
        StateError('A restored mutation requires serialized variables.'),
      );
    }
    return execute(variables);
  }

  Future<TData> _execute(TVariables variables, {required bool restored}) async {
    final context = MutationContext(
      client: client,
      key: options.key,
      meta: Map<String, Object?>.unmodifiable(options.meta),
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
      optimistic = await options.onMutate?.call(variables, context);
      if (optimistic != state.optimistic) {
        _setState(_copyState(optimistic: optimistic));
      }
    }

    var failureCount = state.failureCount;
    try {
      while (true) {
        if (!cache.canRun(this) ||
            (options.networkMode == QueryNetworkMode.online &&
                !client.onlineManager.isOnline)) {
          _setState(_copyState(isPaused: true));
          await cache.waitUntilRunnable(client, this);
        }
        if (state.isPaused) _setState(_copyState(isPaused: false));
        try {
          final data = await options.mutation(variables, context);
          await cache.onSuccess?.call(
            data,
            variables,
            optimistic,
            this,
            context,
          );
          await options.onSuccess?.call(data, variables, optimistic, context);
          await options.onSettled?.call(
            data,
            null,
            variables,
            optimistic,
            context,
          );
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
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
    } finally {
      cache.notify(MutationCacheEvent(MutationCacheEventType.updated, this));
    }
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

  void destroy() {
    _destroyed = true;
    _gcTimer?.cancel();
    _observers.clear();
  }
}

/// Reactive facade that tracks the latest execution of one mutation kind.
final class MutationObserver<TData, TVariables, TOptimistic> {
  MutationObserver(this.client, this.options)
    : _state = MutationState<TData, TVariables, TOptimistic>.idle();

  final QueryClient client;
  final MutationOptions<TData, TVariables, TOptimistic> options;
  MutationState<TData, TVariables, TOptimistic> _state;
  Mutation<TData, TVariables, TOptimistic>? _mutation;
  final Set<void Function(MutationState<TData, TVariables, TOptimistic>)>
  _listeners = <void Function(MutationState<TData, TVariables, TOptimistic>)>{};
  QueryDispose? _removeMutation;

  MutationState<TData, TVariables, TOptimistic> get current => _state;

  QueryDispose subscribe(
    void Function(MutationState<TData, TVariables, TOptimistic> state) listener,
  ) {
    _listeners.add(listener);
    listener(_state);
    return () => _listeners.remove(listener);
  }

  Future<TData> mutate(TVariables variables) {
    _removeMutation?.call();
    _mutation = client.mutationCache.build(client, options);
    _removeMutation = _mutation!.subscribe(_update);
    return _mutation!.execute(variables);
  }

  void reset() {
    _removeMutation?.call();
    _removeMutation = null;
    _mutation = null;
    _update(MutationState<TData, TVariables, TOptimistic>.idle());
  }

  void _update(MutationState<TData, TVariables, TOptimistic> value) {
    _state = value;
    for (final listener
        in List<
          void Function(MutationState<TData, TVariables, TOptimistic>)
        >.of(_listeners)) {
      listener(value);
    }
  }

  void dispose() {
    _removeMutation?.call();
    _listeners.clear();
  }
}

const Object _mutationUnset = Object();
