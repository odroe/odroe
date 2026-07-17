import 'dart:async';

import 'cancellation.dart';
import 'client.dart';
import 'key.dart';

/// Whether a fetch depends on network availability.
enum QueryNetworkMode { online, always, offlineFirst }

/// When an observer-driven lifecycle event may refetch.
enum QueryRefetchPolicy { never, stale, always }

/// Freshness semantics for cached data.
sealed class QueryFreshness {
  const QueryFreshness();

  const factory QueryFreshness.staleAfter(Duration duration) = QueryStaleAfter;

  /// Time never makes data stale, but invalidation still does.
  const factory QueryFreshness.never() = QueryNeverStale;

  /// Data is immutable for the application lifecycle.
  const factory QueryFreshness.static() = QueryStaticData;
}

final class QueryStaleAfter extends QueryFreshness {
  const QueryStaleAfter(this.duration);

  final Duration duration;
}

final class QueryNeverStale extends QueryFreshness {
  const QueryNeverStale();
}

final class QueryStaticData extends QueryFreshness {
  const QueryStaticData();
}

/// Retry decision independent from a particular transport.
final class QueryRetry {
  const QueryRetry._(this._test);

  const QueryRetry.never() : _test = _neverRetry;

  factory QueryRetry.times(int retries) {
    if (retries < 0) throw ArgumentError.value(retries, 'retries');
    return QueryRetry._((failureCount, _) => failureCount <= retries);
  }

  const QueryRetry.forever() : _test = _alwaysRetry;

  const QueryRetry.when(bool Function(int failureCount, Object error) test)
    : _test = test;

  final bool Function(int failureCount, Object error) _test;

  bool shouldRetry(int failureCount, Object error) =>
      _test(failureCount, error);
}

bool _neverRetry(int _, Object _) => false;
bool _alwaysRetry(int _, Object _) => true;

/// Optional policy values layered by client defaults and a query definition.
final class QueryPolicy {
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

  final QueryFreshness? freshness;
  final Duration? gcTime;
  final QueryRetry? retry;
  final Duration Function(int failureCount, Object error)? retryDelay;
  final QueryNetworkMode? networkMode;
  final QueryRefetchPolicy? refetchOnMount;
  final QueryRefetchPolicy? refetchOnFocus;
  final QueryRefetchPolicy? refetchOnReconnect;
  final Duration? refetchInterval;
  final bool? refetchInBackground;
  final bool? enabled;
  final bool? structuralSharing;

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
  const QueryInitialData(this.value, {this.updatedAt});

  final T value;
  final DateTime? updatedAt;
}

/// Metadata describing a fetch beyond the query identity.
final class QueryFetchMeta {
  const QueryFetchMeta({this.kind = 'fetch', this.value});

  final String kind;
  final Object? value;
}

/// Input supplied to a query function.
final class QueryContext {
  QueryContext({
    required this.client,
    required this.key,
    required this.meta,
    required this.fetchMeta,
    required QueryCancelToken cancelToken,
  }) : _cancelToken = cancelToken;

  final QueryClient client;
  final QueryKey key;
  final Map<String, Object?> meta;
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
  const QueryOptions({
    required this.key,
    required this.query,
    this.policy = const QueryPolicy(),
    this.initialData,
    this.meta = const <String, Object?>{},
    this.merge,
  });

  final QueryKey key;
  final QueryFunction<T> query;
  final QueryPolicy policy;
  final QueryInitialData<T>? initialData;
  final Map<String, Object?> meta;
  final QueryDataMerger<T>? merge;
}

/// Fully resolved options owned by one query cache entry.
final class ResolvedQueryOptions<T> {
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

  final QueryKey key;
  final QueryFunction<T>? query;
  final QueryFreshness freshness;
  final Duration gcTime;
  final QueryRetry retry;
  final Duration Function(int failureCount, Object error) retryDelay;
  final QueryNetworkMode networkMode;
  final QueryRefetchPolicy refetchOnMount;
  final QueryRefetchPolicy refetchOnFocus;
  final QueryRefetchPolicy refetchOnReconnect;
  final Duration? refetchInterval;
  final bool refetchInBackground;
  final bool enabled;
  final bool structuralSharing;
  final QueryInitialData<T>? initialData;
  final Map<String, Object?> meta;
  final QueryDataMerger<T>? merge;
}

Duration defaultQueryRetryDelay(int failureCount, Object _) {
  final exponent = failureCount.clamp(0, 30);
  final milliseconds = (1000 * (1 << exponent)).clamp(0, 30000);
  return Duration(milliseconds: milliseconds);
}
