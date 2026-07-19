// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'client.dart';
import 'key.dart';
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
