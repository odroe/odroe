import 'dart:async';

import 'cancellation.dart';
import 'client.dart';
import 'key.dart';

/// Whether a fetch depends on network availability.
enum QueryNetworkMode {
  /// Pause network work while offline.
  online,

  /// Run regardless of connectivity state.
  always,

  /// Try once before pausing subsequent retries offline.
  offlineFirst,
}

/// When an observer-driven lifecycle event may refetch.
enum QueryRefetchPolicy {
  /// Do not refetch for the lifecycle event.
  never,

  /// Refetch only stale data.
  stale,

  /// Refetch regardless of freshness.
  always,
}

/// Freshness semantics for cached data.
sealed class QueryFreshness {
  /// Creates a freshness policy.
  const QueryFreshness();

  /// Becomes stale after [duration].
  const factory QueryFreshness.staleAfter(Duration duration) = QueryStaleAfter;

  /// Time never makes data stale, but invalidation still does.
  const factory QueryFreshness.never() = QueryNeverStale;

  /// Data is immutable for the application lifecycle.
  const factory QueryFreshness.static() = QueryStaticData;
}

/// Data that becomes stale after a duration.
final class QueryStaleAfter extends QueryFreshness {
  /// Creates a timed freshness policy.
  const QueryStaleAfter(this.duration);

  /// How long data remains fresh.
  final Duration duration;
}

/// Data that only becomes stale through invalidation.
final class QueryNeverStale extends QueryFreshness {
  /// Creates an invalidation-only freshness policy.
  const QueryNeverStale();
}

/// Immutable data that cannot be invalidated.
final class QueryStaticData extends QueryFreshness {
  /// Creates a static-data freshness policy.
  const QueryStaticData();
}

/// Retry decision independent from a particular transport.
final class QueryRetry {
  const QueryRetry._(this._test);

  /// Never retries a failed operation.
  const QueryRetry.never() : _test = _neverRetry;

  /// Retries at most [retries] times.
  factory QueryRetry.times(int retries) {
    if (retries < 0) throw ArgumentError.value(retries, 'retries');
    return QueryRetry._((failureCount, _) => failureCount <= retries);
  }

  /// Retries every failure.
  const QueryRetry.forever() : _test = _alwaysRetry;

  /// Uses [test] to decide whether each failure should retry.
  const QueryRetry.when(bool Function(int failureCount, Object error) test)
    : _test = test;

  final bool Function(int failureCount, Object error) _test;

  /// Returns whether the current failure should retry.
  bool shouldRetry(int failureCount, Object error) =>
      _test(failureCount, error);
}

bool _neverRetry(int _, Object _) => false;
bool _alwaysRetry(int _, Object _) => true;

/// Optional policy values layered by client defaults and a query definition.
final class QueryPolicy {
  /// Creates a partial query policy.
  const QueryPolicy({
    this.freshness,
    this.gcTime,
    this.retry,
    this.retryDelay,
    this.networkMode,
    this.refetchOnMount,
    this.refetchOnFocus,
    this.refetchOnReconnect,
    this.refetchInterval,
    this.refetchInBackground,
    this.enabled,
    this.structuralSharing,
  });

  /// How long successful data remains fresh.
  final QueryFreshness? freshness;

  /// How long an unused query remains cached.
  final Duration? gcTime;

  /// The retry decision for failed fetches.
  final QueryRetry? retry;

  /// Computes the delay before each retry.
  final Duration Function(int failureCount, Object error)? retryDelay;

  /// How fetches respond to offline state.
  final QueryNetworkMode? networkMode;

  /// Refetch behavior when the first observer mounts.
  final QueryRefetchPolicy? refetchOnMount;

  /// Refetch behavior when the app regains focus.
  final QueryRefetchPolicy? refetchOnFocus;

  /// Refetch behavior when connectivity returns.
  final QueryRefetchPolicy? refetchOnReconnect;

  /// Optional periodic refetch interval.
  final Duration? refetchInterval;

  /// Whether interval refetches may run without focus.
  final bool? refetchInBackground;

  /// Whether observers may fetch automatically.
  final bool? enabled;

  /// Whether equal subtrees preserve their previous references.
  final bool? structuralSharing;

  /// Layers non-null values from [override] over this policy.
  QueryPolicy merge(QueryPolicy override) => QueryPolicy(
    freshness: override.freshness ?? freshness,
    gcTime: override.gcTime ?? gcTime,
    retry: override.retry ?? retry,
    retryDelay: override.retryDelay ?? retryDelay,
    networkMode: override.networkMode ?? networkMode,
    refetchOnMount: override.refetchOnMount ?? refetchOnMount,
    refetchOnFocus: override.refetchOnFocus ?? refetchOnFocus,
    refetchOnReconnect: override.refetchOnReconnect ?? refetchOnReconnect,
    refetchInterval: override.refetchInterval ?? refetchInterval,
    refetchInBackground: override.refetchInBackground ?? refetchInBackground,
    enabled: override.enabled ?? enabled,
    structuralSharing: override.structuralSharing ?? structuralSharing,
  );
}

/// Explicit initial data, including a valid null value.
final class QueryInitialData<T> {
  /// Creates an initial query value with an optional timestamp.
  const QueryInitialData(this.value, {this.updatedAt});

  /// The initial value.
  final T value;

  /// When the initial value was last updated.
  final DateTime? updatedAt;
}

/// Metadata describing a fetch beyond the query identity.
final class QueryFetchMeta {
  /// Creates metadata for a fetch invocation.
  const QueryFetchMeta({this.kind = 'fetch', this.value});

  /// The caller-defined fetch kind.
  final String kind;

  /// Additional caller-defined data.
  final Object? value;
}

/// Input supplied to a query function.
final class QueryContext {
  /// Creates the context passed to a query function.
  QueryContext({
    required this.client,
    required this.key,
    required this.meta,
    required this.fetchMeta,
    required QueryCancelToken cancelToken,
  }) : _cancelToken = cancelToken;

  /// The client executing the query.
  final QueryClient client;

  /// The query's cache key.
  final QueryKey key;

  /// User metadata from the query definition.
  final Map<String, Object?> meta;

  /// Metadata for this fetch invocation.
  final QueryFetchMeta? fetchMeta;
  final QueryCancelToken _cancelToken;

  /// Marks the underlying operation as cancellation-aware.
  QueryCancelToken get cancelToken => _cancelToken..markConsumed();
}

/// Fetches one typed resource.
typedef QueryFunction<T> = FutureOr<T> Function(QueryContext context);

/// Custom reference-preserving data merger.
typedef QueryDataMerger<T> = T Function(T? previous, T next);

/// A reusable, strongly typed query definition.
final class QueryOptions<T> {
  /// Creates a reusable typed query definition.
  const QueryOptions({
    required this.key,
    required this.query,
    this.policy = const QueryPolicy(),
    this.initialData,
    this.meta = const <String, Object?>{},
    this.merge,
  });

  /// The query's cache key.
  final QueryKey key;

  /// The function that fetches data.
  final QueryFunction<T> query;

  /// Policy overrides for this query.
  final QueryPolicy policy;

  /// Optional data used before the first fetch.
  final QueryInitialData<T>? initialData;

  /// User metadata passed to the query function.
  final Map<String, Object?> meta;

  /// Optional custom structural-sharing merger.
  final QueryDataMerger<T>? merge;
}

/// Fully resolved options owned by one query cache entry.
final class ResolvedQueryOptions<T> {
  /// Creates a complete query runtime configuration.
  const ResolvedQueryOptions({
    required this.key,
    required this.query,
    required this.freshness,
    required this.gcTime,
    required this.retry,
    required this.retryDelay,
    required this.networkMode,
    required this.refetchOnMount,
    required this.refetchOnFocus,
    required this.refetchOnReconnect,
    required this.refetchInterval,
    required this.refetchInBackground,
    required this.enabled,
    required this.structuralSharing,
    required this.initialData,
    required this.meta,
    required this.merge,
  });

  /// The query's cache key.
  final QueryKey key;

  /// The function that fetches data, if registered.
  final QueryFunction<T>? query;

  /// The resolved freshness policy.
  final QueryFreshness freshness;

  /// How long an unused query remains cached.
  final Duration gcTime;

  /// The resolved retry policy.
  final QueryRetry retry;

  /// Computes the delay before each retry.
  final Duration Function(int failureCount, Object error) retryDelay;

  /// The resolved network behavior.
  final QueryNetworkMode networkMode;

  /// Refetch behavior when observers mount.
  final QueryRefetchPolicy refetchOnMount;

  /// Refetch behavior after focus returns.
  final QueryRefetchPolicy refetchOnFocus;

  /// Refetch behavior after connectivity returns.
  final QueryRefetchPolicy refetchOnReconnect;

  /// Optional periodic refetch interval.
  final Duration? refetchInterval;

  /// Whether interval refetches may run without focus.
  final bool refetchInBackground;

  /// Whether observers may fetch automatically.
  final bool enabled;

  /// Whether equal subtrees preserve previous references.
  final bool structuralSharing;

  /// Optional data used before the first fetch.
  final QueryInitialData<T>? initialData;

  /// User metadata passed to the query function.
  final Map<String, Object?> meta;

  /// Optional custom structural-sharing merger.
  final QueryDataMerger<T>? merge;
}

/// Returns the default capped exponential retry delay.
Duration defaultQueryRetryDelay(int failureCount, Object _) {
  final exponent = failureCount.clamp(0, 30);
  final milliseconds = (1000 * (1 << exponent)).clamp(0, 30000);
  return Duration(milliseconds: milliseconds);
}
