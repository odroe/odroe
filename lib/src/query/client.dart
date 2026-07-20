import 'dart:async';

import 'cache.dart';
import 'key.dart';
import 'managers.dart';
import 'mutation.dart';
import 'observer.dart';
import 'options.dart';
import 'query.dart';
import 'state.dart';

/// Selects query cache entries for bulk operations.
final class QueryFilter {
  /// Creates criteria for matching cached queries.
  const QueryFilter({
    this.key,
    this.exact = false,
    this.type = QueryActivity.all,
    this.stale,
    this.fetchStatus,
    this.predicate,
  });

  /// The exact key or key prefix to match.
  final QueryKey? key;

  /// Whether [key] must match the complete query key.
  final bool exact;

  /// Which observer activity state to match.
  final QueryActivity type;

  /// Optional stale-state requirement.
  final bool? stale;

  /// Optional fetch-state requirement.
  final QueryFetchStatus? fetchStatus;

  /// Additional query predicate.
  final bool Function(Query<dynamic> query)? predicate;
}

/// Observer activity used when filtering queries.
enum QueryActivity {
  /// Match every query.
  all,

  /// Match queries with an enabled observer.
  active,

  /// Match queries without an enabled observer.
  inactive,
}

/// Options shared by every query and mutation client operation.
final class QueryClientOptions {
  /// Creates options shared by a query client.
  const QueryClientOptions({
    this.queries = const QueryPolicy(),
    this.environment = const QueryEnvironment(),
  });

  /// Default policy inherited by every query.
  final QueryPolicy queries;

  /// Runtime environment used to select defaults.
  final QueryEnvironment environment;
}

/// Owns query and mutation caches for one app or one server request.
final class QueryClient {
  /// Creates a client with optionally supplied runtime components.
  QueryClient({
    this.options = const QueryClientOptions(),
    QueryCache? queryCache,
    MutationCache? mutationCache,
    QueryFocusManager? focusManager,
    QueryOnlineManager? onlineManager,
    QueryScheduler? scheduler,
  }) : queryCache = queryCache ?? QueryCache(),
       mutationCache = mutationCache ?? MutationCache(),
       focusManager = focusManager ?? QueryFocusManager(),
       onlineManager = onlineManager ?? QueryOnlineManager(),
       scheduler = scheduler ?? const SystemQueryScheduler();

  /// Shared client options.
  final QueryClientOptions options;

  /// Storage for query state machines.
  final QueryCache queryCache;

  /// Storage for mutation executions.
  final MutationCache mutationCache;

  /// Application focus signal.
  final QueryFocusManager focusManager;

  /// Network connectivity signal.
  final QueryOnlineManager onlineManager;

  /// Clock and timer implementation.
  final QueryScheduler scheduler;

  final List<(QueryKey, QueryPolicy)> _queryDefaults =
      <(QueryKey, QueryPolicy)>[];
  final Map<String, MutationOptions<dynamic, dynamic, dynamic>>
  _mutationDefaults = <String, MutationOptions<dynamic, dynamic, dynamic>>{};
  int _mounts = 0;
  QueryDispose? _removeFocus;
  QueryDispose? _removeOnline;

  /// Connects cache behavior to focus and connectivity signals.
  void mount() {
    if (_mounts++ > 0) return;
    _removeFocus = focusManager.subscribe((focused) {
      if (!focused) return;
      unawaited(resumePausedMutations());
      for (final query in queryCache.all) {
        query.onFocus();
      }
    });
    _removeOnline = onlineManager.subscribe((online) {
      if (!online) return;
      unawaited(resumePausedMutations());
      for (final query in queryCache.all) {
        query.onReconnect();
      }
    });
  }

  /// Disconnects one mounted consumer from runtime signals.
  void unmount() {
    if (_mounts == 0 || --_mounts > 0) return;
    _removeFocus?.call();
    _removeOnline?.call();
    _removeFocus = null;
    _removeOnline = null;
  }

  /// Registers a policy inherited by keys beginning with [prefix].
  void setQueryDefaults(QueryKey prefix, QueryPolicy policy) {
    _queryDefaults.removeWhere((entry) => entry.$1 == prefix);
    _queryDefaults.add((prefix, policy));
  }

  /// Resolves client and prefix defaults for [key].
  QueryPolicy getQueryDefaults(QueryKey key) {
    var policy = options.queries;
    for (final entry in _queryDefaults) {
      if (key.startsWith(entry.$1)) policy = policy.merge(entry.$2);
    }
    return policy;
  }

  /// Resolves every runtime option for [value].
  ResolvedQueryOptions<T> resolve<T>(QueryOptions<T> value) {
    final policy = getQueryDefaults(value.key).merge(value.policy);
    final networkMode = policy.networkMode ?? QueryNetworkMode.online;
    return ResolvedQueryOptions<T>(
      key: value.key,
      query: value.query,
      freshness:
          policy.freshness ?? const QueryFreshness.staleAfter(Duration.zero),
      gcTime: policy.gcTime ?? const Duration(minutes: 5),
      retry:
          policy.retry ??
          QueryRetry.times(options.environment.isServer ? 0 : 3),
      retryDelay: policy.retryDelay ?? defaultQueryRetryDelay,
      networkMode: networkMode,
      refetchOnMount: policy.refetchOnMount ?? QueryRefetchPolicy.stale,
      refetchOnFocus: policy.refetchOnFocus ?? QueryRefetchPolicy.stale,
      refetchOnReconnect:
          policy.refetchOnReconnect ??
          (networkMode == QueryNetworkMode.always
              ? QueryRefetchPolicy.never
              : QueryRefetchPolicy.stale),
      refetchInterval: policy.refetchInterval,
      refetchInBackground: policy.refetchInBackground ?? false,
      enabled: policy.enabled ?? true,
      structuralSharing: policy.structuralSharing ?? true,
      initialData: value.initialData,
      meta: Map<String, Object?>.unmodifiable(value.meta),
      merge: value.merge,
    );
  }

  /// Returns or creates the cache entry for [options].
  Query<T> query<T>(QueryOptions<T> options) {
    final existing = queryCache.get<T>(options.key.canonical);
    if (existing != null) {
      existing.setOptions(options);
      return existing;
    }
    final untyped = queryCache.getAny(options.key.canonical);
    final restoredState = untyped == null
        ? null
        : _castQueryState<T>(untyped.state);
    if (untyped != null) queryCache.remove(untyped);
    final resolved = resolve(options);
    final created = Query<T>(
      client: this,
      cache: queryCache,
      options: resolved,
      sourceOptions: options,
      state: restoredState,
    );
    queryCache.add(created);
    return created;
  }

  /// Restores a query before its executable [QueryOptions] are registered.
  Query<T> restoreQuery<T>(
    QueryKey key,
    QueryState<T> state, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final existing = queryCache.getAny(key.canonical);
    if (existing != null) return existing as Query<T>;
    final policy = getQueryDefaults(key);
    final networkMode = policy.networkMode ?? QueryNetworkMode.online;
    final restored = Query<T>(
      client: this,
      cache: queryCache,
      state: state,
      options: ResolvedQueryOptions<T>(
        key: key,
        query: null,
        freshness:
            policy.freshness ?? const QueryFreshness.staleAfter(Duration.zero),
        gcTime: policy.gcTime ?? const Duration(minutes: 5),
        retry:
            policy.retry ??
            QueryRetry.times(options.environment.isServer ? 0 : 3),
        retryDelay: policy.retryDelay ?? defaultQueryRetryDelay,
        networkMode: networkMode,
        refetchOnMount: policy.refetchOnMount ?? QueryRefetchPolicy.stale,
        refetchOnFocus: policy.refetchOnFocus ?? QueryRefetchPolicy.stale,
        refetchOnReconnect:
            policy.refetchOnReconnect ?? QueryRefetchPolicy.stale,
        refetchInterval: policy.refetchInterval,
        refetchInBackground: policy.refetchInBackground ?? false,
        enabled: policy.enabled ?? true,
        structuralSharing: policy.structuralSharing ?? true,
        initialData: null,
        meta: Map<String, Object?>.unmodifiable(meta),
        merge: null,
      ),
    );
    queryCache.add(restored);
    return restored;
  }

  /// Creates an observer for [options].
  QueryObserver<T> observe<T>(QueryOptions<T> options) =>
      QueryObserver<T>(this, options);

  /// Registers executable defaults for mutations with [key].
  void setMutationDefaults<TData, TVariables, TOptimistic>(
    QueryKey key,
    MutationOptions<TData, TVariables, TOptimistic> options,
  ) {
    if (options.key != key) {
      throw ArgumentError('Mutation defaults must use the registered key.');
    }
    _mutationDefaults[key.canonical] = options;
  }

  /// Returns mutation defaults registered for [key].
  MutationOptions<dynamic, dynamic, dynamic>? getMutationDefaults(
    QueryKey key,
  ) => _mutationDefaults[key.canonical];

  /// Creates an observer for a mutation definition.
  MutationObserver<TData, TVariables, TOptimistic>
  observeMutation<TData, TVariables, TOptimistic>(
    MutationOptions<TData, TVariables, TOptimistic> options,
  ) => MutationObserver<TData, TVariables, TOptimistic>(this, options);

  /// Executes one mutation immediately.
  Future<TData> executeMutation<TData, TVariables, TOptimistic>(
    MutationOptions<TData, TVariables, TOptimistic> options,
    TVariables variables,
  ) => mutationCache.build(this, options).execute(variables);

  /// Returns fresh cached data or fetches it.
  Future<T> fetchQuery<T>(QueryOptions<T> options) {
    final target = query(options);
    if (!target.isStale()) return Future<T>.value(target.state.requireData);
    return target.fetch(cancelRefetch: false);
  }

  /// Fetches [options] while reporting errors only through cache state.
  Future<void> prefetchQuery<T>(QueryOptions<T> options) async {
    try {
      await fetchQuery(options);
    } on Object {
      // Prefetch populates cache state; consumers observe the error later.
    }
  }

  /// Returns cached data or fetches it when absent.
  Future<T> ensureQueryData<T>(
    QueryOptions<T> options, {
    bool revalidateIfStale = false,
  }) {
    final target = query(options);
    if (target.state.hasData) {
      if (revalidateIfStale && target.isStale()) {
        unawaited(target.fetch().then<void>((_) {}, onError: (_) {}));
      }
      return Future<T>.value(target.state.requireData);
    }
    return target.fetch(cancelRefetch: false);
  }

  /// Returns cached data for [key], if present.
  T? getQueryData<T>(QueryKey key) =>
      queryCache.getAny(key.canonical)?.state.data as T?;

  /// Returns cached state for [key], if present.
  QueryState<T>? getQueryState<T>(QueryKey key) {
    final state = queryCache.getAny(key.canonical)?.state;
    return state == null ? null : _castQueryState<T>(state);
  }

  /// Updates data for an already registered query.
  T setQueryData<T>(
    QueryKey key,
    T Function(T? previous) update, {
    DateTime? updatedAt,
  }) {
    final target = queryCache.getAny(key.canonical);
    if (target == null) {
      throw StateError(
        'Register QueryOptions for ${key.canonical} before setting its data.',
      );
    }
    return target.setData(update(target.state.data as T?), updatedAt: updatedAt)
        as T;
  }

  /// Returns cached queries matching [filter].
  Iterable<Query<dynamic>> findAll([
    QueryFilter filter = const QueryFilter(),
  ]) => queryCache.all.where((query) => _matches(query, filter));

  /// Counts matching queries that are currently fetching.
  int isFetching([QueryFilter filter = const QueryFilter()]) => findAll(
    QueryFilter(
      key: filter.key,
      exact: filter.exact,
      type: filter.type,
      stale: filter.stale,
      fetchStatus: QueryFetchStatus.fetching,
      predicate: filter.predicate,
    ),
  ).length;

  /// Cancels active fetches matching [filter].
  Future<void> cancelQueries([
    QueryFilter filter = const QueryFilter(),
    bool silent = false,
    bool revert = true,
  ]) async {
    await Future.wait<void>(
      findAll(
        filter,
      ).map((query) => query.cancel(silent: silent, revert: revert)),
    );
  }

  /// Invalidates matching queries and optionally refetches active ones.
  Future<void> invalidateQueries([
    QueryFilter filter = const QueryFilter(),
    bool refetchActive = true,
  ]) async {
    final targets = findAll(filter).toList(growable: false);
    for (final query in targets) {
      query.invalidate();
    }
    if (refetchActive) {
      await Future.wait<void>(
        targets.where((query) => query.isActive && !query.isStatic).map((
          query,
        ) async {
          try {
            await query.fetch();
          } on Object {
            // State carries the background failure.
          }
        }),
      );
    }
  }

  /// Refetches enabled, non-static queries matching [filter].
  Future<void> refetchQueries([
    QueryFilter filter = const QueryFilter(),
  ]) async {
    await Future.wait<void>(
      findAll(filter)
          .where((query) => !query.isDisabled && !query.isStatic)
          .map((query) async {
            try {
              await query.fetch();
            } on Object {
              // Bulk background refetches report through query state.
            }
          }),
    );
  }

  /// Restores matching queries to initial state and refetches active ones.
  Future<void> resetQueries([QueryFilter filter = const QueryFilter()]) async {
    final targets = findAll(filter).toList(growable: false);
    for (final query in targets) {
      query.reset();
    }
    await Future.wait<void>(
      targets.where((query) => query.isActive).map((query) async {
        try {
          await query.fetch();
        } on Object {
          // Reset already exposes the new state.
        }
      }),
    );
  }

  /// Removes queries matching [filter] from the cache.
  void removeQueries([QueryFilter filter = const QueryFilter()]) {
    for (final query in findAll(filter).toList(growable: false)) {
      queryCache.remove(query);
    }
  }

  /// Continues mutations paused by connectivity or serial scopes.
  Future<void> resumePausedMutations() => mutationCache.resumePaused(this);

  /// Removes all query and mutation cache entries.
  void clear() {
    queryCache.clear();
    mutationCache.clear();
  }

  bool _matches(Query<dynamic> query, QueryFilter filter) {
    final key = filter.key;
    if (key != null &&
        (filter.exact ? query.key != key : !query.key.startsWith(key))) {
      return false;
    }
    if (filter.type == QueryActivity.active && !query.isActive) return false;
    if (filter.type == QueryActivity.inactive && query.isActive) return false;
    if (filter.stale case final stale? when query.isStale() != stale) {
      return false;
    }
    if (filter.fetchStatus case final status?
        when query.state.fetchStatus != status) {
      return false;
    }
    return filter.predicate?.call(query) ?? true;
  }
}

QueryState<T> _castQueryState<T>(QueryState<dynamic> state) => QueryState<T>(
  status: state.status,
  fetchStatus: state.fetchStatus,
  hasData: state.hasData,
  data: state.data as T?,
  dataUpdatedAt: state.dataUpdatedAt,
  error: state.error,
  errorStackTrace: state.errorStackTrace,
  errorUpdatedAt: state.errorUpdatedAt,
  dataUpdateCount: state.dataUpdateCount,
  errorUpdateCount: state.errorUpdateCount,
  fetchFailureCount: state.fetchFailureCount,
  fetchFailureReason: state.fetchFailureReason,
  isInvalidated: state.isInvalidated,
  fetchMeta: state.fetchMeta,
);
