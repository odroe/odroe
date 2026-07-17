// ignore_for_file: public_member_api_docs

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
  const QueryFilter({
    this.key,
    this.exact = false,
    this.type = QueryActivity.all,
    this.stale,
    this.fetchStatus,
    this.predicate,
  });

  final QueryKey? key;
  final bool exact;
  final QueryActivity type;
  final bool? stale;
  final QueryFetchStatus? fetchStatus;
  final bool Function(Query<dynamic> query)? predicate;
}

enum QueryActivity { all, active, inactive }

/// Options shared by every query and mutation client operation.
final class QueryClientOptions {
  const QueryClientOptions({
    this.queries = const QueryPolicy(),
    this.environment = const QueryEnvironment(),
  });

  final QueryPolicy queries;
  final QueryEnvironment environment;
}

/// Owns query and mutation caches for one app or one server request.
final class QueryClient {
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

  final QueryClientOptions options;
  final QueryCache queryCache;
  final MutationCache mutationCache;
  final QueryFocusManager focusManager;
  final QueryOnlineManager onlineManager;
  final QueryScheduler scheduler;

  final List<(QueryKey, QueryPolicy)> _queryDefaults =
      <(QueryKey, QueryPolicy)>[];
  final Map<String, MutationOptions<dynamic, dynamic, dynamic>>
  _mutationDefaults = <String, MutationOptions<dynamic, dynamic, dynamic>>{};
  int _mounts = 0;
  QueryDispose? _removeFocus;
  QueryDispose? _removeOnline;

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

  void unmount() {
    if (_mounts == 0 || --_mounts > 0) return;
    _removeFocus?.call();
    _removeOnline?.call();
    _removeFocus = null;
    _removeOnline = null;
  }

  void setQueryDefaults(QueryKey prefix, QueryPolicy policy) {
    _queryDefaults.removeWhere((entry) => entry.$1 == prefix);
    _queryDefaults.add((prefix, policy));
  }

  QueryPolicy getQueryDefaults(QueryKey key) {
    var policy = options.queries;
    for (final entry in _queryDefaults) {
      if (key.startsWith(entry.$1)) policy = policy.merge(entry.$2);
    }
    return policy;
  }

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

  Query<T> query<T>(QueryOptions<T> options) {
    final resolved = resolve(options);
    final existing = queryCache.get<T>(options.key.canonical);
    if (existing != null) {
      existing.setOptions(resolved);
      return existing;
    }
    final untyped = queryCache.getAny(options.key.canonical);
    final restoredState = untyped == null
        ? null
        : _castQueryState<T>(untyped.state);
    if (untyped != null) queryCache.remove(untyped);
    final created = Query<T>(
      client: this,
      cache: queryCache,
      options: resolved,
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

  QueryObserver<T> observe<T>(QueryOptions<T> options) =>
      QueryObserver<T>(this, options);

  void setMutationDefaults<TData, TVariables, TOptimistic>(
    QueryKey key,
    MutationOptions<TData, TVariables, TOptimistic> options,
  ) {
    if (options.key != key) {
      throw ArgumentError('Mutation defaults must use the registered key.');
    }
    _mutationDefaults[key.canonical] = options;
  }

  MutationOptions<dynamic, dynamic, dynamic>? getMutationDefaults(
    QueryKey key,
  ) => _mutationDefaults[key.canonical];

  MutationObserver<TData, TVariables, TOptimistic>
  observeMutation<TData, TVariables, TOptimistic>(
    MutationOptions<TData, TVariables, TOptimistic> options,
  ) => MutationObserver<TData, TVariables, TOptimistic>(this, options);

  Future<TData> executeMutation<TData, TVariables, TOptimistic>(
    MutationOptions<TData, TVariables, TOptimistic> options,
    TVariables variables,
  ) => mutationCache.build(this, options).execute(variables);

  Future<T> fetchQuery<T>(QueryOptions<T> options) {
    final target = query(options);
    if (!target.isStale()) return Future<T>.value(target.state.requireData);
    return target.fetch(cancelRefetch: false);
  }

  Future<void> prefetchQuery<T>(QueryOptions<T> options) async {
    try {
      await fetchQuery(options);
    } on Object {
      // Prefetch populates cache state; consumers observe the error later.
    }
  }

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

  T? getQueryData<T>(QueryKey key) =>
      queryCache.getAny(key.canonical)?.state.data as T?;

  QueryState<T>? getQueryState<T>(QueryKey key) {
    final state = queryCache.getAny(key.canonical)?.state;
    return state == null ? null : _castQueryState<T>(state);
  }

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

  Iterable<Query<dynamic>> findAll([
    QueryFilter filter = const QueryFilter(),
  ]) => queryCache.all.where((query) => _matches(query, filter));

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

  void removeQueries([QueryFilter filter = const QueryFilter()]) {
    for (final query in findAll(filter).toList(growable: false)) {
      queryCache.remove(query);
    }
  }

  Future<void> resumePausedMutations() => mutationCache.resumePaused(this);

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
