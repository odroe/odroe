// ignore_for_file: public_member_api_docs

/// Data lifecycle independent from active transport state.
enum QueryStatus { pending, success, error }

/// Current transport activity.
enum QueryFetchStatus { idle, fetching, paused }

/// Immutable state of one query cache entry.
final class QueryState<T> {
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

  final QueryStatus status;
  final QueryFetchStatus fetchStatus;
  final bool hasData;
  final T? data;
  final DateTime? dataUpdatedAt;
  final Object? error;
  final StackTrace? errorStackTrace;
  final DateTime? errorUpdatedAt;
  final int dataUpdateCount;
  final int errorUpdateCount;
  final int fetchFailureCount;
  final Object? fetchFailureReason;
  final bool isInvalidated;
  final Object? fetchMeta;

  T get requireData {
    if (!hasData) throw StateError('Query has no data.');
    return data as T;
  }

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
