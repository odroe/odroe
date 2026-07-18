// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'client.dart';
import 'key.dart';
import 'mutation.dart';
import 'query.dart';
import 'state.dart';

typedef QuerySerializeData = Object? Function(Object? data);
typedef QueryDeserializeData = Object? Function(Object? data);

/// One serializable query plus an optional in-memory pending channel.
final class DehydratedQuery {
  const DehydratedQuery({
    required this.key,
    required this.state,
    required this.dehydratedAt,
    required this.meta,
    this.pending,
  });

  final QueryKey key;
  final Map<String, Object?> state;
  final DateTime dehydratedAt;
  final Map<String, Object?> meta;

  /// Used by Start streaming; deliberately omitted from [toJson].
  final Future<Object?>? pending;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key.toJson(),
    'state': state,
    'dehydratedAt': dehydratedAt.millisecondsSinceEpoch,
    if (meta.isNotEmpty) 'meta': meta,
  };

  factory DehydratedQuery.fromJson(Map<String, Object?> json) =>
      DehydratedQuery(
        key: QueryKey.fromJson(json['key']),
        state: Map<String, Object?>.from(json['state']! as Map),
        dehydratedAt: DateTime.fromMillisecondsSinceEpoch(
          json['dehydratedAt']! as int,
        ),
        meta: json['meta'] == null
            ? const <String, Object?>{}
            : Map<String, Object?>.from(json['meta']! as Map),
      );
}

/// A paused mutation that can be resumed after its keyed options are registered.
final class DehydratedMutation {
  const DehydratedMutation({
    required this.key,
    required this.state,
    required this.scope,
    required this.meta,
  });

  final QueryKey key;
  final Map<String, Object?> state;
  final String? scope;
  final Map<String, Object?> meta;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key.toJson(),
    'state': state,
    if (scope != null) 'scope': scope,
    if (meta.isNotEmpty) 'meta': meta,
  };

  factory DehydratedMutation.fromJson(Map<String, Object?> json) =>
      DehydratedMutation(
        key: QueryKey.fromJson(json['key']),
        state: Map<String, Object?>.from(json['state']! as Map),
        scope: json['scope'] as String?,
        meta: json['meta'] == null
            ? const <String, Object?>{}
            : Map<String, Object?>.from(json['meta']! as Map),
      );
}

/// Transport-neutral Query snapshot shared by Start and persistence.
final class DehydratedState {
  const DehydratedState({required this.queries, required this.mutations});

  final List<DehydratedQuery> queries;
  final List<DehydratedMutation> mutations;

  Map<String, Object?> toJson() => <String, Object?>{
    'queries': queries.map((query) => query.toJson()).toList(growable: false),
    'mutations': mutations
        .map((mutation) => mutation.toJson())
        .toList(growable: false),
  };

  factory DehydratedState.fromJson(Map<String, Object?> json) =>
      DehydratedState(
        queries: (json['queries'] as List? ?? const <Object?>[])
            .map(
              (value) => DehydratedQuery.fromJson(
                Map<String, Object?>.from(value! as Map),
              ),
            )
            .toList(growable: false),
        mutations: (json['mutations'] as List? ?? const <Object?>[])
            .map(
              (value) => DehydratedMutation.fromJson(
                Map<String, Object?>.from(value! as Map),
              ),
            )
            .toList(growable: false),
      );
}

/// Creates a snapshot suitable for Start handoff or persistence.
DehydratedState dehydrate(
  QueryClient client, {
  QuerySerializeData serializeData = _identity,
  bool Function(Query<dynamic> query)? shouldDehydrateQuery,
  bool Function(Mutation<dynamic, dynamic, dynamic> mutation)?
  shouldDehydrateMutation,
  bool includePending = false,
  bool redactErrors = true,
}) {
  final queryFilter =
      shouldDehydrateQuery ??
      (query) =>
          query.state.status == QueryStatus.success ||
          (includePending && query.state.status == QueryStatus.pending);
  final mutationFilter =
      shouldDehydrateMutation ?? (mutation) => mutation.state.isPaused;
  final now = client.scheduler.now();
  final queries = <DehydratedQuery>[];
  for (final query in client.queryCache.all.where(queryFilter)) {
    final state = query.state;
    queries.add(
      DehydratedQuery(
        key: query.key,
        dehydratedAt: now,
        meta: query.options.meta,
        pending: includePending
            ? query.promise?.then<Object?>((value) => serializeData(value))
            : null,
        state: <String, Object?>{
          'status': state.status.name,
          'hasData': state.hasData,
          if (state.hasData) 'data': serializeData(state.data),
          if (state.dataUpdatedAt != null)
            'dataUpdatedAt': state.dataUpdatedAt!.millisecondsSinceEpoch,
          if (!redactErrors && state.error != null)
            'error': serializeData(state.error),
          if (state.errorUpdatedAt != null)
            'errorUpdatedAt': state.errorUpdatedAt!.millisecondsSinceEpoch,
          'dataUpdateCount': state.dataUpdateCount,
          'errorUpdateCount': state.errorUpdateCount,
          'fetchFailureCount': state.fetchFailureCount,
          'isInvalidated': state.isInvalidated,
        },
      ),
    );
  }

  final mutations = <DehydratedMutation>[];
  for (final mutation in client.mutationCache.all.where(mutationFilter)) {
    final key = mutation.options.key;
    if (key == null) continue;
    mutations.add(
      DehydratedMutation(
        key: key,
        scope: mutation.options.scope,
        meta: mutation.options.meta,
        state: <String, Object?>{
          'status': mutation.state.status.name,
          'isPaused': mutation.state.isPaused,
          'variables': serializeData(mutation.state.variables),
          'optimistic': serializeData(mutation.state.optimistic),
          'failureCount': mutation.state.failureCount,
          if (mutation.state.submittedAt != null)
            'submittedAt': mutation.state.submittedAt!.millisecondsSinceEpoch,
        },
      ),
    );
  }
  return DehydratedState(
    queries: List<DehydratedQuery>.unmodifiable(queries),
    mutations: List<DehydratedMutation>.unmodifiable(mutations),
  );
}

/// Merges a snapshot without overwriting newer client data.
void hydrate(
  QueryClient client,
  DehydratedState dehydrated, {
  QueryDeserializeData deserializeData = _identity,
}) {
  for (final item in dehydrated.queries) {
    final serialized = item.state;
    final serverDataUpdatedAt = serialized['dataUpdatedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            serialized['dataUpdatedAt']! as int,
          );
    final serverErrorUpdatedAt = serialized['errorUpdatedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            serialized['errorUpdatedAt']! as int,
          );
    final now = client.scheduler.now();
    final updatedAt = _translateServerTime(
      serverDataUpdatedAt,
      dehydratedAt: item.dehydratedAt,
      now: now,
    );
    final errorUpdatedAt = _translateServerTime(
      serverErrorUpdatedAt,
      dehydratedAt: item.dehydratedAt,
      now: now,
    );
    final hasData = serialized['hasData']! as bool;
    final existing = client.queryCache.getAny(item.key.canonical);
    if (existing != null) {
      final current = existing.state;
      if (current.hasData && !hasData) continue;
      final currentDataUpdatedAt = current.dataUpdatedAt;
      if (currentDataUpdatedAt != null &&
          (updatedAt == null || !updatedAt.isAfter(currentDataUpdatedAt))) {
        continue;
      }
      final currentErrorUpdatedAt = current.errorUpdatedAt;
      if (!hasData &&
          currentErrorUpdatedAt != null &&
          (errorUpdatedAt == null ||
              !errorUpdatedAt.isAfter(currentErrorUpdatedAt))) {
        continue;
      }
    }
    final status = QueryStatus.values.byName(serialized['status']! as String);
    final state = QueryState<dynamic>.pending().copyWith(
      status: status,
      fetchStatus: QueryFetchStatus.idle,
      hasData: hasData,
      data: hasData ? deserializeData(serialized['data']) : null,
      dataUpdatedAt: updatedAt,
      error: serialized.containsKey('error')
          ? deserializeData(serialized['error'])
          : null,
      errorUpdatedAt: errorUpdatedAt,
      dataUpdateCount: serialized['dataUpdateCount']! as int,
      errorUpdateCount: serialized['errorUpdateCount']! as int,
      fetchFailureCount: serialized['fetchFailureCount']! as int,
      isInvalidated: serialized['isInvalidated']! as bool,
    );
    final query =
        existing ??
        client.restoreQuery<dynamic>(item.key, state, meta: item.meta);
    if (existing != null) query.setState(state);
    final pending = item.pending;
    if (pending != null && existing?.isFetching != true) {
      unawaited(
        query
            .fetch(
              cancelRefetch: false,
              initialFuture: pending.then(deserializeData),
            )
            .then<void>((_) {}, onError: (_) {}),
      );
    }
  }

  for (final item in dehydrated.mutations) {
    final options = client.getMutationDefaults(item.key);
    if (options == null) continue;
    final serialized = item.state;
    client.mutationCache.build<dynamic, dynamic, dynamic>(
      client,
      options,
      state: MutationState<dynamic, dynamic, dynamic>(
        status: MutationStatus.values.byName(serialized['status']! as String),
        data: null,
        error: null,
        errorStackTrace: null,
        failureCount: serialized['failureCount']! as int,
        failureReason: null,
        isPaused: serialized['isPaused']! as bool,
        variables: deserializeData(serialized['variables']),
        optimistic: deserializeData(serialized['optimistic']),
        submittedAt: serialized['submittedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                serialized['submittedAt']! as int,
              ),
      ),
    );
  }
}

DateTime? _translateServerTime(
  DateTime? value, {
  required DateTime dehydratedAt,
  required DateTime now,
}) {
  if (value == null) return null;
  final age = dehydratedAt.difference(value);
  return age.isNegative ? now : now.subtract(age);
}

Object? _identity(Object? value) => value;
