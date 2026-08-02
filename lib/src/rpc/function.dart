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

/// Converts one typed value to a serializer-supported wire value.
typedef ValueEncoder<T> = Object? Function(T value);

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
    this.id,
    this.decodeInput,
    this.method = HttpMethod.post,
    Iterable<Middleware> middleware = const <Middleware>[],
  }) : middleware = List<Middleware>.unmodifiable(middleware) {
    if (id?.isEmpty ?? false) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
  }

  /// User implementation invoked for each request.
  final ServerFunctionHandler<I, O> handler;

  /// Optional stable wire identifier consumed by the file-route compiler.
  ///
  /// Once published to an application, this value is part of its wire
  /// protocol. Manually assembled server runtimes still own the keys in their
  /// function manifest.
  final String? id;

  /// Optional decoder for function input.
  final ValueDecoder<I>? decodeInput;

  /// HTTP method accepted by this function.
  final HttpMethod method;

  /// Middleware applied before [handler].
  final List<Middleware> middleware;

  /// Decodes [data] and invokes [handler].
  ///
  /// Malformed wire values fail as a controlled HTTP 400 before [handler]
  /// starts. Errors thrown by [handler] retain their original semantics.
  FutureOr<Object?> execute(
    Object? data,
    RequestContext request,
    String id, {
    ValueDecoder<Object?>? generatedDecoder,
  }) {
    late final I input;
    try {
      input = I == NoServerInput && data == null
          ? const NoServerInput() as I
          : generatedDecoder != null
          ? generatedDecoder(data) as I
          : decodeInput?.call(data) ?? data as I;
    } on FormatException {
      throw const HttpError(400, 'Invalid server function payload.');
    } on TypeError {
      throw const HttpError(400, 'Invalid server function payload.');
    } on RangeError {
      throw const HttpError(400, 'Invalid server function payload.');
    } on ArgumentError {
      throw const HttpError(400, 'Invalid server function payload.');
    }
    return handler(
      ServerFunctionContext<I>(data: input, request: request, id: id),
    );
  }
}

/// Generated manifest entry joining an implementation to its wire codecs.
final class ServerFunctionBinding {
  /// Creates a manifest binding for [function].
  const ServerFunctionBinding(
    this.function, {
    this.decodeInput,
    this.encodeOutput,
  });

  /// Bound server implementation.
  final ServerFunction<dynamic, dynamic> function;

  /// Decoder generated from the shared input type.
  final ValueDecoder<Object?>? decodeInput;

  /// Encoder generated for one output value or stream item.
  final ValueEncoder<Object?>? encodeOutput;

  /// HTTP method accepted by the bound function.
  HttpMethod get method => function.method;

  /// Middleware applied to the bound function.
  List<Middleware> get middleware => function.middleware;

  /// Executes the binding with its generated decoder.
  FutureOr<Object?> execute(Object? data, RequestContext request, String id) =>
      function.execute(data, request, id, generatedDecoder: decodeInput);
}
