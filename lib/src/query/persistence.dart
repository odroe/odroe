import 'dart:async';

import 'cache.dart';
import 'client.dart';
import 'hydration.dart';
import 'managers.dart';
import 'mutation.dart';

/// Versioned persisted Query payload.
final class PersistedQueryClient {
  /// Creates a versioned persisted snapshot.
  const PersistedQueryClient({
    required this.timestamp,
    required this.buster,
    required this.state,
  });

  /// When the snapshot was written.
  final DateTime timestamp;

  /// Application-defined cache version.
  final String buster;

  /// The dehydrated Query state.
  final DehydratedState state;

  /// Encodes this snapshot as JSON-compatible data.
  Map<String, Object?> toJson() => <String, Object?>{
    'timestamp': timestamp.millisecondsSinceEpoch,
    'buster': buster,
    'state': state.toJson(),
  };

  /// Decodes a persisted snapshot from JSON-compatible data.
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
  /// Replaces the stored snapshot with [client].
  FutureOr<void> save(PersistedQueryClient client);

  /// Reads the stored snapshot, if present.
  FutureOr<PersistedQueryClient?> restore();

  /// Deletes the stored snapshot.
  FutureOr<void> remove();
}

/// Restores a QueryClient and coalesces subsequent cache writes.
final class QueryPersistence {
  /// Creates persistence for [client] through [persister].
  QueryPersistence({
    required this.client,
    required this.persister,
    this.buster = '',
    this.maxAge = const Duration(days: 1),
    this.writeDelay = const Duration(milliseconds: 100),
    this.serializeData = _persistenceIdentity,
    this.deserializeData = _persistenceIdentity,
  });

  /// The client whose caches are persisted.
  final QueryClient client;

  /// The storage adapter.
  final QueryPersister persister;

  /// Cache version required during restore.
  final String buster;

  /// Maximum accepted snapshot age.
  final Duration maxAge;

  /// Delay used to coalesce cache writes.
  final Duration writeDelay;

  /// Converts query data into storage-safe values.
  final QuerySerializeData serializeData;

  /// Restores query data from stored values.
  final QueryDeserializeData deserializeData;

  QueryDispose? _removeQueries;
  QueryDispose? _removeMutations;
  Timer? _writeTimer;
  Future<void> _saveTail = Future<void>.value();
  bool _disposed = false;

  /// Restores an accepted snapshot and starts listening for cache changes.
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

  /// Saves one current snapshot after any pending save.
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

  /// Cancels the write delay and waits for a current save.
  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    await save();
  }

  /// Stops persistence listeners and delayed writes.
  void dispose() {
    _disposed = true;
    _writeTimer?.cancel();
    _removeQueries?.call();
    _removeMutations?.call();
  }
}

Object? _persistenceIdentity(Object? value) => value;
