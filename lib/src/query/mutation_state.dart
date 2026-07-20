import 'dart:async';

import 'client.dart';
import 'key.dart';
import 'options.dart';

/// Lifecycle status of one mutation execution.
enum MutationStatus {
  /// The mutation has not started.
  idle,

  /// The mutation is running or paused.
  pending,

  /// The mutation completed successfully.
  success,

  /// The mutation completed with an error.
  error,
}

/// Immutable state of one mutation execution.
final class MutationState<TData, TVariables, TOptimistic> {
  /// Creates a complete immutable mutation state.
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

  /// Creates the state before a mutation runs.
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

  /// The mutation lifecycle status.
  final MutationStatus status;

  /// The successful result, when available.
  final TData? data;

  /// The terminal or latest retry error.
  final Object? error;

  /// The stack trace associated with [error].
  final StackTrace? errorStackTrace;

  /// The number of consecutive failures.
  final int failureCount;

  /// The latest failure that may still be retried.
  final Object? failureReason;

  /// Whether execution is waiting for connectivity.
  final bool isPaused;

  /// The variables passed to the current execution.
  final TVariables? variables;

  /// The optimistic value returned before execution.
  final TOptimistic? optimistic;

  /// When the current execution was submitted.
  final DateTime? submittedAt;

  /// Whether the mutation has not started.
  bool get isIdle => status == MutationStatus.idle;

  /// Whether the mutation is running or paused.
  bool get isPending => status == MutationStatus.pending;

  /// Whether the mutation succeeded.
  bool get isSuccess => status == MutationStatus.success;

  /// Whether the mutation failed.
  bool get isError => status == MutationStatus.error;
}

/// Input shared by mutation lifecycle callbacks.
final class MutationContext {
  /// Creates callback context for a mutation.
  const MutationContext({
    required this.client,
    required this.key,
    required this.meta,
  });

  /// The client executing the mutation.
  final QueryClient client;

  /// The optional mutation key.
  final QueryKey? key;

  /// User metadata attached to the mutation.
  final Map<String, Object?> meta;
}

/// Executes a mutation from typed variables.
typedef MutationFunction<TData, TVariables> =
    FutureOr<TData> Function(TVariables variables, MutationContext context);

/// Runs before a mutation and may return an optimistic value.
typedef MutationOnMutate<TVariables, TOptimistic> =
    FutureOr<TOptimistic> Function(
      TVariables variables,
      MutationContext context,
    );

/// Runs after a mutation succeeds.
typedef MutationOnSuccess<TData, TVariables, TOptimistic> =
    FutureOr<void> Function(
      TData data,
      TVariables variables,
      TOptimistic? optimistic,
      MutationContext context,
    );

/// Runs after a mutation fails.
typedef MutationOnError<TVariables, TOptimistic> =
    FutureOr<void> Function(
      Object error,
      StackTrace stackTrace,
      TVariables variables,
      TOptimistic? optimistic,
      MutationContext context,
    );

/// Runs after a mutation settles with either data or an error.
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
  /// Creates a typed mutation definition.
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

  /// The operation executed for each mutation.
  final MutationFunction<TData, TVariables> mutation;

  /// The optional key used for defaults and filtering.
  final QueryKey? key;

  /// Mutations in the same non-null scope execute serially.
  final String? scope;

  /// The retry policy for failed executions.
  final QueryRetry retry;

  /// Computes the delay before a retry.
  final Duration Function(int failureCount, Object error) retryDelay;

  /// Controls execution while offline.
  final QueryNetworkMode networkMode;

  /// How long an unused mutation remains cached.
  final Duration gcTime;

  /// User metadata exposed to callbacks.
  final Map<String, Object?> meta;

  /// Callback invoked before execution.
  final MutationOnMutate<TVariables, TOptimistic>? onMutate;

  /// Callback invoked after success.
  final MutationOnSuccess<TData, TVariables, TOptimistic>? onSuccess;

  /// Callback invoked after failure.
  final MutationOnError<TVariables, TOptimistic>? onError;

  /// Callback invoked after either outcome.
  final MutationOnSettled<TData, TVariables, TOptimistic>? onSettled;
}
