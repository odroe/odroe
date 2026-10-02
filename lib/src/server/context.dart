import '../app/context.dart';
import '../app/registry.dart';
import 'http.dart';
import 'invocation.dart';

/// Type-safe identity used to extend one request context.
final class RequestKey<T> {
  /// Creates a request-local key.
  ///
  /// Keys use instance identity. Keep one key and reuse that exact instance
  /// when storing and reading a value. The name is only for diagnostics.
  RequestKey(this.name);

  /// The name shown in diagnostics.
  final String name;

  /// Stores [value] in [context] under this key.
  void set(RequestContext context, T value) {
    context._values[this as RequestKey<Object?>] = value;
  }

  @override
  String toString() => 'RequestKey<$T>($name)';
}

/// Mutable request-scoped state shared by middleware and handlers.
final class RequestContext {
  /// Creates a request context backed by an application context.
  RequestContext({
    required this.request,
    required this.app,
    ServerInvocation? invocation,
  }) {
    if (invocation != null) _invocationKey.set(this, invocation);
  }

  /// The incoming request.
  final ServerRequest request;

  /// Explicitly installed application modules for this request.
  final AppContext app;

  final Map<RequestKey<Object?>, Object?> _values =
      <RequestKey<Object?>, Object?>{};

  static final _invocationKey = RequestKey<ServerInvocation>(
    'server.invocation',
  );

  /// Adapter-owned state for this request.
  ServerInvocation get invocation =>
      get(_invocationKey) ?? ServerInvocation.empty;

  /// Reads an application service.
  T read<T extends Object>(ContextKey<T> key) => app.read(key);

  /// Reads an optional application service.
  T? maybe<T extends Object>(ContextKey<T> key) => app.maybe(key);

  /// Reads a request-local value.
  T? get<T>(RequestKey<T> key) => _values[key as RequestKey<Object?>] as T?;

  /// Reads a required request-local value.
  T require<T>(RequestKey<T> key) {
    final value = get(key);
    if (value == null) {
      throw StateError('Missing request context: ${key.name}.');
    }
    return value;
  }

  /// Whether a request-local value exists for [key].
  bool contains<T>(RequestKey<T> key) => _values.containsKey(key);
}

/// A redirect control-flow result understood by routes and RPC.
final class Redirect implements Exception {
  /// Creates a redirect to [location].
  const Redirect(this.location, {this.status = 302});

  /// Redirect target.
  final Uri location;

  /// Redirect status code.
  final int status;
}

/// A not-found control-flow result understood by routes and RPC.
final class NotFound implements Exception {
  /// Creates a not-found result.
  const NotFound([this.message = 'Not found']);

  /// Public failure message.
  final String message;
}

/// An explicit HTTP failure from application code.
final class HttpError implements Exception {
  /// Creates an HTTP failure.
  const HttpError(this.status, this.message, {this.headers});

  /// Response status code.
  final int status;

  /// Public failure message.
  final String message;

  /// Optional response headers.
  final Headers? headers;
}
