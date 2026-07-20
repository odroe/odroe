/// Data lifecycle independent from active transport state.
enum QueryStatus {
  /// No successful result has been stored yet.
  pending,

  /// The query holds a successful result.
  success,

  /// The latest fetch failed.
  error,
}

/// Current transport activity.
enum QueryFetchStatus {
  /// No fetch is active.
  idle,

  /// A fetch is running.
  fetching,

  /// A fetch is waiting for its network mode.
  paused,
}

/// Immutable state of one query cache entry.
final class QueryState<T> {
  /// Creates a complete immutable query state.
  const QueryState({
    required this.status,
    required this.fetchStatus,
    required this.hasData,
    required this.data,
    required this.dataUpdatedAt,
    required this.error,
    required this.errorStackTrace,
    required this.errorUpdatedAt,
    required this.dataUpdateCount,
    required this.errorUpdateCount,
    required this.fetchFailureCount,
    required this.fetchFailureReason,
    required this.isInvalidated,
    required this.fetchMeta,
  });

  /// Creates the initial state before data has been fetched.
  factory QueryState.pending() => QueryState<T>(
    status: QueryStatus.pending,
    fetchStatus: QueryFetchStatus.idle,
    hasData: false,
    data: null,
    dataUpdatedAt: null,
    error: null,
    errorStackTrace: null,
    errorUpdatedAt: null,
    dataUpdateCount: 0,
    errorUpdateCount: 0,
    fetchFailureCount: 0,
    fetchFailureReason: null,
    isInvalidated: false,
    fetchMeta: null,
  );

  /// The data lifecycle status.
  final QueryStatus status;

  /// The current fetch activity.
  final QueryFetchStatus fetchStatus;

  /// Whether [data] is present, including a present nullable value.
  final bool hasData;

  /// The last successful data value.
  final T? data;

  /// When [data] was last updated.
  final DateTime? dataUpdatedAt;

  /// The latest fetch error.
  final Object? error;

  /// The stack trace associated with [error].
  final StackTrace? errorStackTrace;

  /// When [error] was recorded.
  final DateTime? errorUpdatedAt;

  /// Number of successful data updates.
  final int dataUpdateCount;

  /// Number of error updates.
  final int errorUpdateCount;

  /// Consecutive failures in the current fetch.
  final int fetchFailureCount;

  /// The latest failure that may still be retried.
  final Object? fetchFailureReason;

  /// Whether the cached data was explicitly invalidated.
  final bool isInvalidated;

  /// Metadata associated with the current fetch.
  final Object? fetchMeta;

  /// Returns the stored data or throws when no data is present.
  T get requireData {
    if (!hasData) throw StateError('Query has no data.');
    return data as T;
  }

  /// Returns a state with the selected values replaced.
  QueryState<T> copyWith({
    QueryStatus? status,
    QueryFetchStatus? fetchStatus,
    bool? hasData,
    Object? data = _unset,
    Object? dataUpdatedAt = _unset,
    Object? error = _unset,
    Object? errorStackTrace = _unset,
    Object? errorUpdatedAt = _unset,
    int? dataUpdateCount,
    int? errorUpdateCount,
    int? fetchFailureCount,
    Object? fetchFailureReason = _unset,
    bool? isInvalidated,
    Object? fetchMeta = _unset,
  }) => QueryState<T>(
    status: status ?? this.status,
    fetchStatus: fetchStatus ?? this.fetchStatus,
    hasData: hasData ?? this.hasData,
    data: identical(data, _unset) ? this.data : data as T?,
    dataUpdatedAt: identical(dataUpdatedAt, _unset)
        ? this.dataUpdatedAt
        : dataUpdatedAt as DateTime?,
    error: identical(error, _unset) ? this.error : error,
    errorStackTrace: identical(errorStackTrace, _unset)
        ? this.errorStackTrace
        : errorStackTrace as StackTrace?,
    errorUpdatedAt: identical(errorUpdatedAt, _unset)
        ? this.errorUpdatedAt
        : errorUpdatedAt as DateTime?,
    dataUpdateCount: dataUpdateCount ?? this.dataUpdateCount,
    errorUpdateCount: errorUpdateCount ?? this.errorUpdateCount,
    fetchFailureCount: fetchFailureCount ?? this.fetchFailureCount,
    fetchFailureReason: identical(fetchFailureReason, _unset)
        ? this.fetchFailureReason
        : fetchFailureReason,
    isInvalidated: isInvalidated ?? this.isInvalidated,
    fetchMeta: identical(fetchMeta, _unset) ? this.fetchMeta : fetchMeta,
  );
}

const Object _unset = Object();
