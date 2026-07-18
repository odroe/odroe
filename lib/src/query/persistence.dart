// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'cache.dart';
import 'client.dart';
import 'hydration.dart';
import 'managers.dart';
import 'mutation.dart';

/// Versioned persisted Query payload.
final class PersistedQueryClient {
  const PersistedQueryClient({
    required this.timestamp,
    required this.buster,
    required this.state,
  });

  final DateTime timestamp;
  final String buster;
  final DehydratedState state;

  Map<String, Object?> toJson() => <String, Object?>{
    'timestamp': timestamp.millisecondsSinceEpoch,
    'buster': buster,
    'state': state.toJson(),
  };

  factory PersistedQueryClient.fromJson(Map<String, Object?> json) =>
      PersistedQueryClient(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          json['timestamp']! as int,
        ),
        buster: json['buster']! as String,
        state: DehydratedState.fromJson(
          Map<String, Object?>.from(json['state']! as Map),
        ),
      );
}

/// Storage adapter implemented by files, preferences, databases, or memory.
abstract interface class QueryPersister {
  FutureOr<void> save(PersistedQueryClient client);
  FutureOr<PersistedQueryClient?> restore();
  FutureOr<void> remove();
}

/// Restores a QueryClient and coalesces subsequent cache writes.
final class QueryPersistence {
  QueryPersistence({
    required this.client,
    required this.persister,
    this.buster = '',
    this.maxAge = const Duration(days: 1),
    this.writeDelay = const Duration(milliseconds: 100),
    this.serializeData = _persistenceIdentity,
    this.deserializeData = _persistenceIdentity,
  });

  final QueryClient client;
  final QueryPersister persister;
  final String buster;
  final Duration maxAge;
  final Duration writeDelay;
  final QuerySerializeData serializeData;
  final QueryDeserializeData deserializeData;

  QueryDispose? _removeQueries;
  QueryDispose? _removeMutations;
  Timer? _writeTimer;
  Future<void> _saveTail = Future<void>.value();
  bool _disposed = false;

  Future<void> restoreAndListen() async {
    if (_disposed) throw StateError('QueryPersistence is disposed.');
    try {
      final persisted = await persister.restore();
      if (persisted != null) {
        final expired =
            client.scheduler.now().difference(persisted.timestamp) > maxAge;
        if (expired || persisted.buster != buster) {
          await persister.remove();
        } else {
          hydrate(client, persisted.state, deserializeData: deserializeData);
        }
      }
    } on Object {
      await persister.remove();
      rethrow;
    }
    if (_disposed) return;
    _removeQueries = client.queryCache.subscribe((event) {
      if (event.type == QueryCacheEventType.added ||
          event.type == QueryCacheEventType.removed ||
          event.type == QueryCacheEventType.updated) {
        _scheduleSave();
      }
    });
    _removeMutations = client.mutationCache.subscribe((event) {
      if (event.type == MutationCacheEventType.added ||
          event.type == MutationCacheEventType.removed ||
          event.type == MutationCacheEventType.updated) {
        _scheduleSave();
      }
    });
  }

  void _scheduleSave() {
    if (_disposed) return;
    _writeTimer?.cancel();
    _writeTimer = client.scheduler.timer(writeDelay, () {
      unawaited(save().then<void>((_) {}, onError: (_) {}));
    });
  }

  Future<void> save() {
    if (_disposed) return Future<void>.value();
    final snapshot = PersistedQueryClient(
      timestamp: client.scheduler.now(),
      buster: buster,
      state: dehydrate(client, serializeData: serializeData),
    );
    final previous = _saveTail.then<void>((_) {}, onError: (_) {});
    final operation = previous.then<void>((_) async {
      await persister.save(snapshot);
    });
    _saveTail = operation;
    return operation;
  }

  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    await save();
  }

  void dispose() {
    _disposed = true;
    _writeTimer?.cancel();
    _removeQueries?.call();
    _removeMutations?.call();
  }
}

Object? _persistenceIdentity(Object? value) => value;
