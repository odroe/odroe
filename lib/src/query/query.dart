import 'dart:async';

import 'cache.dart';
import 'cancellation.dart';
import 'client.dart';
import 'key.dart';
import 'options.dart';
import 'state.dart';

/// Internal contract implemented by reactive query observers.
abstract interface class QueryObserverHandle {
  /// Whether this observer permits automatic fetching.
  bool get enabled;

  /// Whether this observer treats data as immutable.
  bool get isStatic;

  /// Whether regaining focus should refetch the query.
  bool shouldRefetchOnFocus();

  /// Whether reconnecting should refetch the query.
  bool shouldRefetchOnReconnect();

  /// Starts a fetch requested by a runtime signal.
  void fetchForSignal();

  /// Receives query state changes.
  void onQueryUpdate();
}

/// One asynchronous server-state machine stored by [QueryCache].
final class Query<T> {
  /// Creates one query cache entry.
  Query({
    required this.client,
    required this.cache,
    required ResolvedQueryOptions<T> options,
    QueryOptions<T>? sourceOptions,
    QueryState<T>? state,
  }) : options = options,
       _sourceOptions = sourceOptions,
       state = state ?? _initialState(options) {
    _initialStateValue = this.state;
    scheduleGc();
  }

  /// The client that owns this query.
  final QueryClient client;

  /// The cache that stores this query.
  final QueryCache cache;

  /// The resolved runtime options.
  ResolvedQueryOptions<T> options;

  /// The current immutable state.
  QueryState<T> state;

  QueryOptions<T>? _sourceOptions;
  late QueryState<T> _initialStateValue;
  final Set<QueryObserverHandle> _observers = <QueryObserverHandle>{};
  Timer? _gcTimer;
  Future<T>? _inFlight;
  QueryCancellationController? _cancellation;
  int _fetchId = 0;
  bool _destroyed = false;

  /// The query's cache key.
  QueryKey get key => options.key;

  /// The active fetch, if any.
  Future<T>? get promise => _inFlight;

  /// Whether a fetch is active.
  bool get isFetching => _inFlight != null;

  /// Whether any observer permits automatic fetching.
  bool get isActive => _observers.any((observer) => observer.enabled);

  /// Whether this query currently has no active observer.
  bool get isDisabled => _observers.isNotEmpty ? !isActive : !options.enabled;

  /// Whether every observer treats this query as immutable.
  bool get isStatic => _observers.isEmpty
      ? options.freshness is QueryStaticData
      : _observers.every((observer) => observer.isStatic);

  /// Returns whether data is missing, invalidated, or outside [freshness].
  bool isStale([QueryFreshness? freshness, DateTime? now]) {
    if (!state.hasData || state.isInvalidated) return true;
    return switch (freshness ?? options.freshness) {
      QueryStaticData() || QueryNeverStale() => false,
      QueryStaleAfter(:final duration) =>
        (now ?? client.scheduler.now()).difference(state.dataUpdatedAt!) >=
            duration,
    };
  }

  /// Applies a new source definition to this cache entry.
  void setOptions(QueryOptions<T> value) {
    if (identical(_sourceOptions, value)) return;
    _sourceOptions = value;
    options = client.resolve(value);
    scheduleGc();
  }

  /// Attaches a reactive observer.
  void addObserver(QueryObserverHandle observer) {
    if (_observers.add(observer)) {
      _gcTimer?.cancel();
      _gcTimer = null;
      cache.notify(QueryCacheEvent(QueryCacheEventType.observerAdded, this));
    }
  }

  /// Detaches a reactive observer.
  void removeObserver(QueryObserverHandle observer) {
    if (!_observers.remove(observer)) return;
    cache.notify(QueryCacheEvent(QueryCacheEventType.observerRemoved, this));
    if (_observers.isEmpty && _cancellation?.consumed == true) {
      cancel(silent: true, revert: true);
    }
    scheduleGc();
  }

  /// Schedules removal after the configured unused lifetime.
  void scheduleGc() {
    _gcTimer?.cancel();
    if (_destroyed || _observers.isNotEmpty) return;
    final duration = options.gcTime;
    if (duration == Duration.zero) {
      scheduleMicrotask(_removeIfUnused);
      return;
    }
    _gcTimer = client.scheduler.timer(duration, _removeIfUnused);
  }

  void _removeIfUnused() {
    if (_observers.isEmpty && !isFetching) cache.remove(this);
  }

  /// Stores successful [value] and returns the structurally shared result.
  T setData(
    T value, {
    DateTime? updatedAt,
    bool manual = true,
    ResolvedQueryOptions<T>? resolved,
  }) {
    final dataOptions = resolved ?? options;
    final T merged;
    if (dataOptions.merge case final merge?) {
      merged = merge(state.hasData ? state.data : null, value);
    } else if (dataOptions.structuralSharing) {
      final shared = structurallyShare(
        state.hasData ? state.data : null,
        value,
      );
      merged = shared is T ? shared : value;
    } else {
      merged = value;
    }
    _setState(
      state.copyWith(
        status: QueryStatus.success,
        fetchStatus: manual ? state.fetchStatus : QueryFetchStatus.idle,
        hasData: true,
        data: merged,
        dataUpdatedAt: updatedAt ?? client.scheduler.now(),
        error: null,
        errorStackTrace: null,
        dataUpdateCount: state.dataUpdateCount + 1,
        fetchFailureCount: manual ? state.fetchFailureCount : 0,
        fetchFailureReason: manual ? state.fetchFailureReason : null,
        isInvalidated: false,
        fetchMeta: manual ? state.fetchMeta : null,
      ),
    );
    return merged;
  }

  /// Replaces the complete query state.
  void setState(QueryState<T> value) => _setState(value);

  /// Marks non-static data stale.
  void invalidate() {
    if (isStatic || state.isInvalidated) return;
    _setState(state.copyWith(isInvalidated: true));
  }

  /// Restores initial state and cancels active work.
  void reset() {
    cancel(silent: true, revert: false);
    _setState(_initialStateValue);
    scheduleGc();
  }

  /// Fetches data, deduplicating or replacing active work as configured.
  Future<T> fetch({
    ResolvedQueryOptions<T>? options,
    bool cancelRefetch = true,
    QueryFetchMeta? meta,
    Future<T>? initialFuture,
  }) {
    final active = _inFlight;
    if (active != null) {
      if (!cancelRefetch || !state.hasData) return active;
      cancel(silent: true, revert: true);
    }

    final fetchOptions = options ?? this.options;
    final query = fetchOptions.query;
    if (query == null && initialFuture == null) {
      return Future<T>.error(
        StateError('No query function is registered for ${key.canonical}.'),
      );
    }

    final fetchId = ++_fetchId;
    final previous = state;
    final cancellation = QueryCancellationController();
    _cancellation = cancellation;
    final canStart = _canStart(fetchOptions);
    _setState(
      state.copyWith(
        fetchStatus: canStart
            ? QueryFetchStatus.fetching
            : QueryFetchStatus.paused,
        fetchFailureCount: 0,
        fetchFailureReason: null,
        fetchMeta: meta,
        status: state.hasData ? state.status : QueryStatus.pending,
      ),
    );

    late final Future<T> future;
    future =
        _run(
          fetchId: fetchId,
          previous: previous,
          cancellation: cancellation,
          options: fetchOptions,
          meta: meta,
          initialFuture: initialFuture,
        ).whenComplete(() {
          if (identical(_inFlight, future)) {
            _inFlight = null;
            _cancellation = null;
            scheduleGc();
          }
        });
    _inFlight = future;
    return future;
  }

  Future<T> _run({
    required int fetchId,
    required QueryState<T> previous,
    required QueryCancellationController cancellation,
    required ResolvedQueryOptions<T> options,
    required QueryFetchMeta? meta,
    required Future<T>? initialFuture,
  }) async {
    var failureCount = 0;
    var firstAttempt = true;
    try {
      while (true) {
        if (!_canStart(options) &&
            !(firstAttempt &&
                options.networkMode == QueryNetworkMode.offlineFirst)) {
          await _waitForRuntime(cancellation, fetchId, options);
        }
        if (fetchId == _fetchId &&
            state.fetchStatus != QueryFetchStatus.fetching) {
          _setState(state.copyWith(fetchStatus: QueryFetchStatus.fetching));
        }

        try {
          final operation = firstAttempt && initialFuture != null
              ? initialFuture
              : Future<T>.sync(
                  () => options.query!(
                    QueryContext(
                      client: client,
                      key: key,
                      meta: options.meta,
                      fetchMeta: meta,
                      cancelToken: cancellation.token,
                    ),
                  ),
                );
          final result = await Future.any<T>(<Future<T>>[
            operation,
            cancellation.whenCancelled.then<T>((reason) => throw reason),
          ]);
          if (fetchId == _fetchId) {
            setData(result, manual: false, resolved: options);
          }
          return result;
        } on QueryCancelledException {
          rethrow;
        } on Object catch (error, stackTrace) {
          failureCount++;
          final retry = options.retry.shouldRetry(failureCount, error);
          if (!retry) {
            if (fetchId == _fetchId) {
              _setState(
                state.copyWith(
                  status: QueryStatus.error,
                  fetchStatus: QueryFetchStatus.idle,
                  error: error,
                  errorStackTrace: stackTrace,
                  errorUpdatedAt: client.scheduler.now(),
                  errorUpdateCount: state.errorUpdateCount + 1,
                  fetchFailureCount: failureCount,
                  fetchFailureReason: error,
                  fetchMeta: null,
                ),
              );
            }
            Error.throwWithStackTrace(error, stackTrace);
          }
          if (fetchId == _fetchId) {
            _setState(
              state.copyWith(
                fetchFailureCount: failureCount,
                fetchFailureReason: error,
              ),
            );
          }
          await _delay(
            options.retryDelay(failureCount - 1, error),
            cancellation,
          );
          if (!_canContinue(options)) {
            await _waitForRuntime(cancellation, fetchId, options);
          }
        }
        firstAttempt = false;
      }
    } on QueryCancelledException catch (cancelled) {
      if (fetchId == _fetchId) {
        if (cancelled.revert) {
          _setState(previous.copyWith(fetchStatus: QueryFetchStatus.idle));
        } else {
          _setState(
            state.copyWith(fetchStatus: QueryFetchStatus.idle, fetchMeta: null),
          );
        }
      }
      rethrow;
    }
  }

  bool _canStart(ResolvedQueryOptions<T> options) =>
      options.networkMode != QueryNetworkMode.online ||
      client.onlineManager.isOnline;

  bool _canContinue(ResolvedQueryOptions<T> options) =>
      client.focusManager.isFocused &&
      (options.networkMode == QueryNetworkMode.always ||
          client.onlineManager.isOnline);

  Future<void> _delay(
    Duration duration,
    QueryCancellationController cancellation,
  ) async {
    if (duration <= Duration.zero) {
      cancellation.token.throwIfCancelled();
      return;
    }
    final completer = Completer<void>();
    final timer = client.scheduler.timer(duration, completer.complete);
    try {
      await Future.any<void>(<Future<void>>[
        completer.future,
        cancellation.whenCancelled.then<void>((reason) => throw reason),
      ]);
    } finally {
      timer.cancel();
    }
  }

  Future<void> _waitForRuntime(
    QueryCancellationController cancellation,
    int fetchId,
    ResolvedQueryOptions<T> options,
  ) async {
    if (fetchId == _fetchId && state.fetchStatus != QueryFetchStatus.paused) {
      _setState(state.copyWith(fetchStatus: QueryFetchStatus.paused));
    }
    if (_canContinue(options)) return;
    final ready = Completer<void>();
    void check(_) {
      if (_canContinue(options) && !ready.isCompleted) ready.complete();
    }

    final removeFocus = client.focusManager.subscribe(check);
    final removeOnline = client.onlineManager.subscribe(check);
    try {
      await Future.any<void>(<Future<void>>[
        ready.future,
        cancellation.whenCancelled.then<void>((reason) => throw reason),
      ]);
    } finally {
      removeFocus();
      removeOnline();
    }
  }

  /// Cancels the active fetch and waits for it to stop.
  Future<void> cancel({bool silent = false, bool revert = true}) async {
    final future = _inFlight;
    _cancellation?.cancel(silent: silent, revert: revert);
    if (future != null) {
      try {
        await future;
      } on QueryCancelledException {
        // Cancellation is the successful outcome of this operation.
      }
    }
  }

  /// Handles application focus returning.
  void onFocus() {
    for (final observer in _observers) {
      if (observer.shouldRefetchOnFocus()) {
        observer.fetchForSignal();
        return;
      }
    }
  }

  /// Handles network connectivity returning.
  void onReconnect() {
    for (final observer in _observers) {
      if (observer.shouldRefetchOnReconnect()) {
        observer.fetchForSignal();
        return;
      }
    }
  }

  void _setState(QueryState<T> value) {
    if (_destroyed) return;
    state = value;
    for (final observer in List<QueryObserverHandle>.of(_observers)) {
      observer.onQueryUpdate();
    }
    cache.notify(QueryCacheEvent(QueryCacheEventType.updated, this));
  }

  /// Stops timers, cancellation, and observer notifications.
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _gcTimer?.cancel();
    _cancellation?.cancel(silent: true, revert: false);
    _observers.clear();
  }
}

QueryState<T> _initialState<T>(ResolvedQueryOptions<T> options) {
  final initial = options.initialData;
  if (initial == null) return QueryState<T>.pending();
  return QueryState<T>.pending().copyWith(
    status: QueryStatus.success,
    hasData: true,
    data: initial.value,
    dataUpdatedAt: initial.updatedAt ?? DateTime.now(),
  );
}
