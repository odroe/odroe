// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import 'context.dart';
import 'middleware.dart';
import 'request.dart';
import 'serialization.dart';

/// Input marker for a server function without arguments.
final class NoServerInput {
  const NoServerInput();
}

/// Context supplied to a server-function implementation.
final class ServerFunctionContext<I> {
  const ServerFunctionContext({
    required this.data,
    required this.request,
    required this.id,
  });

  final I data;
  final StartRequestContext request;
  final String id;
}

typedef ServerFunctionHandler<I, O> =
    FutureOr<O> Function(ServerFunctionContext<I> context);

/// Erased server-function implementation stored by generated manifests.
abstract interface class AnyServerFunction {
  String? get id;
  StartMethod get method;
  List<StartMiddleware> get middleware;
  AnyServerFunction bind(String id);
  FutureOr<Object?> executeObject(
    Object? data,
    StartRequestContext request,
    String id,
  );
}

/// A server-only implementation discovered and registered by the Start compiler.
final class ServerFunction<I, O> implements AnyServerFunction {
  ServerFunction({
    required this.handler,
    this.method = StartMethod.post,
    Iterable<StartMiddleware> middleware = const <StartMiddleware>[],
  }) : middleware = List<StartMiddleware>.unmodifiable(middleware),
       id = null;

  ServerFunction._({
    required this.handler,
    required this.method,
    required this.middleware,
    required this.id,
  });

  final ServerFunctionHandler<I, O> handler;

  @override
  final StartMethod method;

  @override
  final List<StartMiddleware> middleware;

  @override
  final String? id;

  @override
  ServerFunction<I, O> bind(String id) => ServerFunction<I, O>._(
    handler: handler,
    method: method,
    middleware: middleware,
    id: id,
  );

  @override
  FutureOr<Object?> executeObject(
    Object? data,
    StartRequestContext request,
    String id,
  ) {
    final input = I == NoServerInput && data == null
        ? const NoServerInput() as I
        : data as I;
    return handler(
      ServerFunctionContext<I>(data: input, request: request, id: id),
    );
  }
}

/// A generated, client-safe reference to one server function.
final class ServerFunctionRef<I, O> {
  const ServerFunctionRef({required this.id, this.method = StartMethod.post});

  final String id;
  final StartMethod method;

  Future<O> call(StartRpcClient client, I data) => client.call(this, data);
}

/// A generated, client-safe reference to a streaming server function.
final class ServerStreamFunctionRef<I, T> {
  const ServerStreamFunctionRef({
    required this.id,
    this.method = StartMethod.post,
  });

  final String id;
  final StartMethod method;

  Future<Stream<T>> call(StartRpcClient client, I data) =>
      client.stream(this, data);
}

/// Adapter used by RPC clients; HTTP is only one possible implementation.
abstract interface class StartTransport {
  Future<StartResponse> send(StartRequest request);
}

/// Executes requests in memory without a socket or HTTP server.
final class InMemoryStartTransport implements StartTransport {
  const InMemoryStartTransport(this.handler);

  final FutureOr<StartResponse> Function(StartRequest request) handler;

  @override
  Future<StartResponse> send(StartRequest request) async => handler(request);
}

/// Typed server-function client using the shared Start wire protocol.
final class StartRpcClient {
  StartRpcClient({
    required this.baseUri,
    required this.transport,
    StartSerializer? serializer,
    this.functionPath = '/__odroe/functions',
  }) : serializer = serializer ?? StartSerializer();

  final Uri baseUri;
  final StartTransport transport;
  final StartSerializer serializer;
  final String functionPath;

  Future<O> call<I, O>(ServerFunctionRef<I, O> function, I data) async {
    final response = await _send(function.id, function.method, data);
    if (O == StartResponse) return response as O;
    final contentType = response.headers.value('content-type') ?? '';
    if (contentType.startsWith('application/x-ndjson')) {
      throw const StartProtocolException(
        'The server returned a stream for a non-streaming function reference.',
      );
    }
    final frame = await _readFrame(response);
    return _decodeFrame<O>(frame, response.status);
  }

  Future<Stream<T>> stream<I, T>(
    ServerStreamFunctionRef<I, T> function,
    I data,
  ) async {
    final response = await _send(function.id, function.method, data);
    final contentType = response.headers.value('content-type') ?? '';
    if (!contentType.startsWith('application/x-ndjson')) {
      final frame = await _readFrame(response);
      _decodeFrame<Object?>(frame, response.status);
      throw const StartProtocolException(
        'The server returned one value for a streaming function reference.',
      );
    }
    return response.body
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.isNotEmpty)
        .map<dynamic>((line) {
          final frame = Map<String, Object?>.from(jsonDecode(line) as Map);
          if (frame['type'] == 'error') {
            throw RemoteServerException(
              frame['message'] as String? ?? 'Server stream failed.',
              status: response.status,
            );
          }
          return serializer.decode(frame['data']);
        })
        .cast<T>();
  }

  Future<StartResponse> _send<I>(String id, StartMethod method, I data) async {
    final payload = serializer.encodeJson(<String, Object?>{
      'data': data is NoServerInput ? null : data,
    });
    final path = '$functionPath/${Uri.encodeComponent(id)}';
    late final StartRequest request;
    if (method == StartMethod.get) {
      final target = baseUri
          .resolve(path)
          .replace(queryParameters: <String, String>{'payload': payload});
      request = StartRequest.bytes(
        method: StartMethod.get,
        uri: target,
        headers: _rpcHeaders(baseUri),
      );
    } else {
      request = StartRequest.bytes(
        method: method,
        uri: baseUri.resolve(path),
        headers: _rpcHeaders(baseUri)
          ..set('content-type', 'application/json; charset=utf-8'),
        body: utf8.encode(payload),
      );
    }
    return transport.send(request);
  }

  Future<Map<String, Object?>> _readFrame(StartResponse response) async {
    final text = await response.readText();
    return text.isEmpty
        ? <String, Object?>{'type': 'data', 'data': null}
        : Map<String, Object?>.from(jsonDecode(text) as Map);
  }

  O _decodeFrame<O>(Map<String, Object?> frame, int status) {
    switch (frame['type']) {
      case 'data':
        return serializer.decode(frame['data']) as O;
      case 'redirect':
        throw StartRedirect(
          Uri.parse(frame['location']! as String),
          status: frame['status']! as int,
        );
      case 'notFound':
        throw StartNotFound(frame['message'] as String? ?? 'Not found');
      default:
        throw RemoteServerException(
          frame['message'] as String? ?? 'Server function failed.',
          status: status,
          remoteType: frame['errorType'] as String?,
        );
    }
  }
}

/// The client and server disagreed about the function's response shape.
final class StartProtocolException implements Exception {
  const StartProtocolException(this.message);

  final String message;

  @override
  String toString() => 'StartProtocolException: $message';
}

StartHeaders _rpcHeaders(Uri baseUri) => StartHeaders.single(<String, String>{
  'accept': 'application/json, application/x-ndjson',
  'x-odroe-server-function': 'true',
  'origin': _origin(baseUri),
});

String _origin(Uri uri) {
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

/// Sanitized error returned by a remote server function.
final class RemoteServerException implements Exception {
  const RemoteServerException(
    this.message, {
    required this.status,
    this.remoteType,
  });

  final String message;
  final int status;
  final String? remoteType;

  @override
  String toString() => remoteType == null
      ? 'RemoteServerException($status): $message'
      : 'RemoteServerException($status, $remoteType): $message';
}
