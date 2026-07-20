import 'dart:async';
import 'dart:convert';

import '../server/context.dart';
import '../server/http.dart';
import 'function.dart';
import 'serializer.dart';

/// Typed reference to a server function that returns one value.
final class ServerFunctionRef<I, O> {
  /// Creates a reference emitted by the route compiler.
  const ServerFunctionRef({
    required this.id,
    this.method = HttpMethod.post,
    this.decodeOutput,
  });

  /// Stable function identifier in the server manifest.
  final String id;

  /// HTTP method used to invoke the function.
  final HttpMethod method;

  /// Optional decoder for the serialized result.
  final ValueDecoder<O>? decodeOutput;

  /// Invokes this function through [client].
  Future<O> call(RpcClient client, I data) => client.call(this, data);
}

/// Typed reference to a server function that returns a stream.
final class ServerStreamFunctionRef<I, T> {
  /// Creates a streaming reference emitted by the route compiler.
  const ServerStreamFunctionRef({
    required this.id,
    this.method = HttpMethod.post,
    this.decodeOutput,
  });

  /// Stable function identifier in the server manifest.
  final String id;

  /// HTTP method used to invoke the function.
  final HttpMethod method;

  /// Optional decoder for each serialized stream item.
  final ValueDecoder<T>? decodeOutput;

  /// Invokes this function through [client].
  Future<Stream<T>> call(RpcClient client, I data) => client.stream(this, data);
}

/// Sends RPC requests without coupling the client to an HTTP implementation.
abstract interface class RpcTransport {
  /// Sends [request] and returns its response.
  Future<ServerResponse> send(ServerRequest request);
}

/// Typed client for generated server-function references.
final class RpcClient {
  /// Creates a client for one Odroe server origin.
  RpcClient({
    required this.baseUri,
    required this.transport,
    Serializer? serializer,
    this.functionPath = '/__odroe/functions',
  }) : serializer = serializer ?? Serializer();

  /// Origin used to resolve server-function URLs.
  final Uri baseUri;

  /// Transport used for every request.
  final RpcTransport transport;

  /// Serializer used for request and response values.
  final Serializer serializer;

  /// URL prefix for server-function endpoints.
  final String functionPath;

  /// Calls a value-returning server [function].
  Future<O> call<I, O>(ServerFunctionRef<I, O> function, I data) async {
    final response = await _send(function.id, function.method, data);
    if (O == ServerResponse) return response as O;
    final contentType = response.headers.value('content-type') ?? '';
    if (contentType.startsWith('application/x-ndjson')) {
      throw const RpcProtocolException(
        'The server returned a stream for a value function.',
      );
    }
    return _decodeFrame<O>(
      await _readFrame(response),
      response.status,
      decode: function.decodeOutput,
    );
  }

  /// Calls a streaming server [function].
  Future<Stream<T>> stream<I, T>(
    ServerStreamFunctionRef<I, T> function,
    I data,
  ) async {
    final response = await _send(function.id, function.method, data);
    final contentType = response.headers.value('content-type') ?? '';
    if (!contentType.startsWith('application/x-ndjson')) {
      _decodeFrame<Object?>(await _readFrame(response), response.status);
      throw const RpcProtocolException(
        'The server returned one value for a streaming function.',
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
          final value = serializer.decode(frame['data']);
          return function.decodeOutput?.call(value) ?? value;
        })
        .cast<T>();
  }

  Future<ServerResponse> _send<I>(String id, HttpMethod method, I data) {
    final payload = serializer.encodeJson(<String, Object?>{
      'data': data is NoServerInput ? null : data,
    });
    final path = '$functionPath/${Uri.encodeComponent(id)}';
    if (method == HttpMethod.get) {
      return transport.send(
        ServerRequest.bytes(
          method: method,
          uri: baseUri
              .resolve(path)
              .replace(queryParameters: <String, String>{'payload': payload}),
          headers: _rpcHeaders(baseUri),
        ),
      );
    }
    return transport.send(
      ServerRequest.bytes(
        method: method,
        uri: baseUri.resolve(path),
        headers: _rpcHeaders(baseUri)
          ..set('content-type', 'application/json; charset=utf-8'),
        body: utf8.encode(payload),
      ),
    );
  }

  Future<Map<String, Object?>> _readFrame(ServerResponse response) async {
    final text = await response.readText();
    return text.isEmpty
        ? <String, Object?>{'type': 'data', 'data': null}
        : Map<String, Object?>.from(jsonDecode(text) as Map);
  }

  O _decodeFrame<O>(
    Map<String, Object?> frame,
    int status, {
    ValueDecoder<O>? decode,
  }) {
    switch (frame['type']) {
      case 'data':
        final value = serializer.decode(frame['data']);
        return decode?.call(value) ?? value as O;
      case 'redirect':
        throw Redirect(
          Uri.parse(frame['location']! as String),
          status: frame['status']! as int,
        );
      case 'notFound':
        throw NotFound(frame['message'] as String? ?? 'Not found');
      default:
        throw RemoteServerException(
          frame['message'] as String? ?? 'Server function failed.',
          status: status,
          remoteType: frame['errorType'] as String?,
        );
    }
  }
}

/// Indicates that a response violated the RPC wire protocol.
final class RpcProtocolException implements Exception {
  /// Creates a protocol exception with a human-readable [message].
  const RpcProtocolException(this.message);

  /// Description of the protocol violation.
  final String message;

  @override
  String toString() => 'RpcProtocolException: $message';
}

Headers _rpcHeaders(Uri baseUri) => Headers.single(<String, String>{
  'accept': 'application/json, application/x-ndjson',
  'x-odroe-server-function': 'true',
  'origin': _origin(baseUri),
});

String _origin(Uri uri) {
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

/// Error returned by a remote server function.
final class RemoteServerException implements Exception {
  /// Creates an exception from an RPC error frame.
  const RemoteServerException(
    this.message, {
    required this.status,
    this.remoteType,
  });

  /// Error message supplied by the server.
  final String message;

  /// HTTP response status.
  final int status;

  /// Optional remote exception type name.
  final String? remoteType;

  @override
  String toString() => remoteType == null
      ? 'RemoteServerException($status): $message'
      : 'RemoteServerException($status, $remoteType): $message';
}
