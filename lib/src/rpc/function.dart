import 'dart:async';

import '../server/context.dart';
import '../server/http.dart';
import '../server/middleware.dart';

/// Input marker for a server function without arguments.
final class NoServerInput {
  /// Creates the no-input marker.
  const NoServerInput();
}

/// Converts one decoded wire value to [T].
typedef ValueDecoder<T> = T Function(Object? value);

/// Request data available to a server-function handler.
final class ServerFunctionContext<I> {
  /// Creates a context for one invocation.
  const ServerFunctionContext({
    required this.data,
    required this.request,
    required this.id,
  });

  /// Decoded function input.
  final I data;

  /// Current server request context.
  final RequestContext request;

  /// Stable identifier of the invoked function.
  final String id;
}

/// Handles one server-function invocation.
typedef ServerFunctionHandler<I, O> =
    FutureOr<O> Function(ServerFunctionContext<I> context);

/// One server-only RPC implementation.
final class ServerFunction<I, O> {
  /// Creates a server function and its invocation policy.
  ServerFunction({
    required this.handler,
    this.decodeInput,
    this.method = HttpMethod.post,
    Iterable<Middleware> middleware = const <Middleware>[],
  }) : middleware = List<Middleware>.of(middleware, growable: false);

  /// User implementation invoked for each request.
  final ServerFunctionHandler<I, O> handler;

  /// Optional decoder for function input.
  final ValueDecoder<I>? decodeInput;

  /// HTTP method accepted by this function.
  final HttpMethod method;

  /// Middleware applied before [handler].
  final List<Middleware> middleware;

  /// Decodes [data] and invokes [handler].
  FutureOr<Object?> execute(
    Object? data,
    RequestContext request,
    String id, {
    ValueDecoder<Object?>? generatedDecoder,
  }) {
    final input = I == NoServerInput && data == null
        ? const NoServerInput() as I
        : generatedDecoder != null
        ? generatedDecoder(data) as I
        : decodeInput?.call(data) ?? data as I;
    return handler(
      ServerFunctionContext<I>(data: input, request: request, id: id),
    );
  }
}

/// Generated manifest entry joining an implementation to its wire decoder.
final class ServerFunctionBinding {
  /// Creates a manifest binding for [function].
  const ServerFunctionBinding(this.function, {this.decodeInput});

  /// Bound server implementation.
  final ServerFunction<dynamic, dynamic> function;

  /// Decoder generated from the shared input type.
  final ValueDecoder<Object?>? decodeInput;

  /// HTTP method accepted by the bound function.
  HttpMethod get method => function.method;

  /// Middleware applied to the bound function.
  List<Middleware> get middleware => function.middleware;

  /// Executes the binding with its generated decoder.
  FutureOr<Object?> execute(Object? data, RequestContext request, String id) =>
      function.execute(data, request, id, generatedDecoder: decodeInput);
}
