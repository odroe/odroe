// ignore_for_file: public_member_api_docs

import '../query/client.dart';
import 'http.dart';

/// Type-safe identity used to extend one request context.
final class ContextKey<T> {
  const ContextKey(this.name);

  final String name;

  @override
  String toString() => 'ContextKey<$T>($name)';
}

/// Mutable request-scoped state shared by middleware and handlers.
final class RequestContext {
  RequestContext({required this.request, required this.query});

  final ServerRequest request;
  final QueryClient query;
  final Map<ContextKey<Object?>, Object?> _values =
      <ContextKey<Object?>, Object?>{};

  T? get<T>(ContextKey<T> key) => _values[key as ContextKey<Object?>] as T?;

  T require<T>(ContextKey<T> key) {
    final value = get(key);
    if (value == null) {
      throw StateError('Missing request context: ${key.name}.');
    }
    return value;
  }

  void set<T>(ContextKey<T> key, T value) {
    _values[key as ContextKey<Object?>] = value;
  }

  bool contains<T>(ContextKey<T> key) => _values.containsKey(key);
}

/// A redirect control-flow result understood by routes and RPC.
final class Redirect implements Exception {
  const Redirect(this.location, {this.status = 302});

  final Uri location;
  final int status;
}

/// A not-found control-flow result understood by routes and RPC.
final class NotFound implements Exception {
  const NotFound([this.message = 'Not found']);

  final String message;
}

/// An explicit HTTP failure from application code.
final class HttpError implements Exception {
  const HttpError(this.status, this.message, {this.headers});

  final int status;
  final String message;
  final Headers? headers;
}
