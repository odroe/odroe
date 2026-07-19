// ignore_for_file: public_member_api_docs

import 'dart:async';

import '../server/context.dart';
import '../server/http.dart';
import '../server/middleware.dart';

/// Input marker for a server function without arguments.
final class NoServerInput {
  const NoServerInput();
}

typedef ValueDecoder<T> = T Function(Object? value);

final class ServerFunctionContext<I> {
  const ServerFunctionContext({
    required this.data,
    required this.request,
    required this.id,
  });

  final I data;
  final RequestContext request;
  final String id;
}

typedef ServerFunctionHandler<I, O> =
    FutureOr<O> Function(ServerFunctionContext<I> context);

/// One server-only RPC implementation.
final class ServerFunction<I, O> {
  ServerFunction({
    required this.handler,
    this.decodeInput,
    this.method = HttpMethod.post,
    Iterable<Middleware> middleware = const <Middleware>[],
  }) : middleware = List<Middleware>.of(middleware, growable: false);

  final ServerFunctionHandler<I, O> handler;
  final ValueDecoder<I>? decodeInput;
  final HttpMethod method;
  final List<Middleware> middleware;

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
  const ServerFunctionBinding(this.function, {this.decodeInput});

  final ServerFunction<dynamic, dynamic> function;
  final ValueDecoder<Object?>? decodeInput;

  HttpMethod get method => function.method;
  List<Middleware> get middleware => function.middleware;

  FutureOr<Object?> execute(Object? data, RequestContext request, String id) =>
      function.execute(data, request, id, generatedDecoder: decodeInput);
}
