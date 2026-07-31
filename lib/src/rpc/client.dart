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

/// Creates application-owned headers immediately before one RPC request.
typedef RpcHeadersProvider = FutureOr<Headers> Function();

/// Typed client for generated server-function references.
final class RpcClient {
  /// Creates a client for one Odroe server origin.
  RpcClient({
    required this.baseUri,
    required this.transport,
    Serializer? serializer,
    this.headersProvider,
    this.functionPath = '/__odroe/functions',
  }) : serializer = serializer ?? Serializer();

  /// Origin used to resolve server-function URLs.
  final Uri baseUri;

  /// Transport used for every request.
  final RpcTransport transport;

  /// Serializer used for request and response values.
  final Serializer serializer;

  /// Creates fresh application headers for every value or stream request.
  ///
  /// Odroe copies the result before applying its protocol-owned headers.
  final RpcHeadersProvider? headersProvider;

  /// URL prefix for server-function endpoints.
  final String functionPath;

  /// Calls a value-returning server [function].
  Future<O> call<I, O>(ServerFunctionRef<I, O> function, I data) async {
    final response = await _send(function.id, function.method, data);
    if (O == ServerResponse) return response as O;
    final contentType = response.headers.value('content-type') ?? '';
    if (contentType.startsWith('application/x-ndjson')) {
      await _cancelBody(response.body);
      if (!_isSuccessful(response.status)) {
        _invalidResponse(
          response.status,
          'The server returned a stream for a failed value request.',
        );
      }
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
    if (!_isSuccessful(response.status)) {
      await _cancelBody(response.body);
      _invalidResponse(
        response.status,
        'The server returned a stream for a failed stream request.',
      );
    }
    return response.body
        .transform(utf8.decoder)
        .handleError(
          (Object _) => _invalidResponse(
            response.status,
            'The server returned invalid RPC stream text.',
          ),
          test: (error) => error is FormatException,
        )
        .transform(const LineSplitter())
        .where((line) => line.isNotEmpty)
        .map<dynamic>((line) {
          final frame = _parseFrame(line, response.status);
          switch (frame['type']) {
            case 'data':
              final value = serializer.decode(frame['data']);
              return function.decodeOutput?.call(value) ?? value;
            case 'error':
              _throwRemoteError(
                frame,
                response.status,
                'Server stream failed.',
              );
            default:
              _invalidResponse(
                response.status,
                'The server returned an unknown RPC stream frame.',
              );
          }
        })
        .cast<T>();
  }

  Future<ServerResponse> _send<I>(String id, HttpMethod method, I data) async {
    final payload = serializer.encodeJson(<String, Object?>{
      'data': data is NoServerInput ? null : data,
    });
    final path = '$functionPath/${Uri.encodeComponent(id)}';
    final headers = _rpcHeaders(baseUri, await headersProvider?.call());
    if (method == HttpMethod.get) {
      return transport.send(
        ServerRequest.bytes(
          method: method,
          uri: baseUri
              .resolve(path)
              .replace(queryParameters: <String, String>{'payload': payload}),
          headers: headers,
        ),
      );
    }
    headers.set('content-type', 'application/json; charset=utf-8');
    return transport.send(
      ServerRequest.bytes(
        method: method,
        uri: baseUri.resolve(path),
        headers: headers,
        body: utf8.encode(payload),
      ),
    );
  }

  Future<Map<String, Object?>> _readFrame(ServerResponse response) async {
    late final String text;
    try {
      text = await response.readText();
    } on FormatException {
      _invalidResponse(
        response.status,
        'The server returned invalid RPC text.',
      );
    }
    if (text.isEmpty) {
      if (_isSuccessful(response.status)) {
        return <String, Object?>{'type': 'data', 'data': null};
      }
      _invalidResponse(
        response.status,
        'The server returned an empty RPC response.',
      );
    }
    return _parseFrame(text, response.status);
  }

  Map<String, Object?> _parseFrame(String text, int status) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      _invalidResponse(status, 'The server returned malformed RPC JSON.');
    }
    if (decoded is! Map) {
      _invalidResponse(status, 'The server returned a non-object RPC frame.');
    }
    return Map<String, Object?>.from(decoded);
  }

  Never _invalidResponse(int status, String protocolMessage) {
    if (!_isSuccessful(status)) {
      throw RemoteServerException(
        'The server returned HTTP $status without an RPC error frame.',
        status: status,
      );
    }
    throw RpcProtocolException(protocolMessage);
  }

  O _decodeFrame<O>(
    Map<String, Object?> frame,
    int status, {
    ValueDecoder<O>? decode,
  }) {
    switch (frame['type']) {
      case 'data':
        if (!_isSuccessful(status)) {
          _invalidResponse(
            status,
            'The server returned data for a failed RPC request.',
          );
        }
        final value = serializer.decode(frame['data']);
        return decode?.call(value) ?? value as O;
      case 'redirect':
        final location = frame['location'];
        final redirectStatus = frame['status'];
        if (location is! String || redirectStatus is! int) {
          _invalidResponse(status, 'The server returned an invalid redirect.');
        }
        final parsedLocation = Uri.tryParse(location);
        if (parsedLocation == null) {
          _invalidResponse(status, 'The server returned an invalid redirect.');
        }
        throw Redirect(parsedLocation, status: redirectStatus);
      case 'notFound':
        final message = frame['message'];
        if (message != null && message is! String) {
          _invalidResponse(
            status,
            'The server returned an invalid not-found frame.',
          );
        }
        throw NotFound(message as String? ?? 'Not found');
      case 'error':
        _throwRemoteError(frame, status, 'Server function failed.');
      default:
        _invalidResponse(status, 'The server returned an unknown RPC frame.');
    }
  }

  Never _throwRemoteError(
    Map<String, Object?> frame,
    int status,
    String fallbackMessage,
  ) {
    final message = frame['message'];
    final remoteType = frame['errorType'];
    if ((message != null && message is! String) ||
        (remoteType != null && remoteType is! String)) {
      _invalidResponse(
        status,
        'The server returned an invalid RPC error frame.',
      );
    }
    throw RemoteServerException(
      message as String? ?? fallbackMessage,
      status: status,
      remoteType: remoteType as String?,
    );
  }
}

Future<void> _cancelBody(Stream<List<int>> body) async {
  final subscription = body.listen(
    null,
    onError: (Object _) {
      // The response is already being rejected by its HTTP or content type.
    },
  );
  await subscription.cancel();
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

Headers _rpcHeaders(Uri baseUri, Headers? applicationHeaders) {
  final headers = applicationHeaders?.copy() ?? Headers();
  return headers
    ..set('accept', 'application/json, application/x-ndjson')
    ..set('x-odroe-server-function', 'true')
    ..set('origin', _origin(baseUri));
}

bool _isSuccessful(int status) => status >= 200 && status < 300;

String _origin(Uri uri) {
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

/// Error returned by a remote RPC or HTTP failure.
final class RemoteServerException implements Exception {
  /// Creates a classified remote failure.
  const RemoteServerException(
    this.message, {
    required this.status,
    this.remoteType,
  });

  /// Server-supplied or locally classified error message.
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
