// ignore_for_file: public_member_api_docs

import '../query/client.dart';
import 'request.dart';

/// Type-safe identity used to extend one request context.
final class StartContextKey<T> {
  const StartContextKey(this.name);

  final String name;

  @override
  String toString() => 'StartContextKey<$T>($name)';
}

/// The Start pipeline currently handling a request.
enum StartHandlerType { router, serverRoute, serverFunction }

/// Mutable request-scoped state shared by middleware and handlers.
final class StartRequestContext {
  StartRequestContext({
    required this.request,
    required this.query,
    required this.type,
  });

  final StartRequest request;
  final QueryClient query;
  StartHandlerType type;
  final Map<StartContextKey<Object?>, Object?> _values =
      <StartContextKey<Object?>, Object?>{};

  T? get<T>(StartContextKey<T> key) =>
      _values[key as StartContextKey<Object?>] as T?;

  T require<T>(StartContextKey<T> key) {
    final value = get(key);
    if (value == null) {
      throw StateError('Missing request context: ${key.name}.');
    }
    return value;
  }

  void set<T>(StartContextKey<T> key, T value) {
    _values[key as StartContextKey<Object?>] = value;
  }

  bool contains<T>(StartContextKey<T> key) => _values.containsKey(key);
}

/// A redirect control-flow result understood by routes and RPC.
final class StartRedirect implements Exception {
  const StartRedirect(this.location, {this.status = 302});

  final Uri location;
  final int status;
}

/// A not-found control-flow result understood by routes and RPC.
final class StartNotFound implements Exception {
  const StartNotFound([this.message = 'Not found']);

  final String message;
}

/// An explicit HTTP failure from application code.
final class StartHttpException implements Exception {
  const StartHttpException(this.status, this.message, {this.headers});

  final int status;
  final String message;
  final StartHeaders? headers;
}
