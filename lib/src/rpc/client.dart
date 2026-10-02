import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../server/context.dart';
import '../server/http.dart';
import 'cancellation.dart';
import 'function.dart';
import 'path.dart';
import 'serializer.dart';

/// Typed reference to a server function that returns one value.
final class ServerFunctionRef<I, O> {
  /// Creates a reference emitted by the route compiler.
  const ServerFunctionRef({
    required this.id,
    this.method = HttpMethod.post,
    this.encodeInput,
    this.decodeOutput,
  });

  /// Stable function identifier in the server manifest.
  final String id;

  /// HTTP method used to invoke the function.
  final HttpMethod method;

  /// Optional encoder applied before the input reaches [Serializer].
  final ValueEncoder<I>? encodeInput;

  /// Optional decoder for the serialized result.
  final ValueDecoder<O>? decodeOutput;

  /// Invokes this function through [client].
  ///
  /// Completing [cancelled] stops the request with [RpcCancelledException].
  Future<O> call(RpcClient client, I data, {Future<void>? cancelled}) =>
      client.call(this, data, cancelled: cancelled);
}

/// Typed reference to a server function that returns a stream.
final class ServerStreamFunctionRef<I, T> {
  /// Creates a streaming reference emitted by the route compiler.
  const ServerStreamFunctionRef({
    required this.id,
    this.method = HttpMethod.post,
    this.encodeInput,
    this.decodeOutput,
  });

  /// Stable function identifier in the server manifest.
  final String id;

  /// HTTP method used to invoke the function.
  final HttpMethod method;

  /// Optional encoder applied before the input reaches [Serializer].
  final ValueEncoder<I>? encodeInput;

  /// Optional decoder for each serialized stream item.
  final ValueDecoder<T>? decodeOutput;

  /// Invokes this function through [client].
  ///
  /// Completing [cancelled] stops request and response streaming with
  /// [RpcCancelledException].
  Future<Stream<T>> call(RpcClient client, I data, {Future<void>? cancelled}) =>
      client.stream(this, data, cancelled: cancelled);
}

/// Sends RPC requests without coupling the client to an HTTP implementation.
abstract interface class RpcTransport {
  /// Sends [request] and returns its response.
  ///
  /// Implementations must stop request and response work when
  /// [ServerRequest.cancelled] completes.
  Future<ServerResponse> send(ServerRequest request);
}

/// Creates application-owned headers immediately before one RPC request.
typedef RpcHeadersProvider = FutureOr<Headers> Function();

/// Typed client for generated server-function references.
final class RpcClient {
  /// Default maximum size of one typed response frame: 1 MiB.
  static const int defaultMaxResponseFrameBytes = 1024 * 1024;

  /// Creates a client for one Odroe server origin.
  RpcClient({
    required this.baseUri,
    required this.transport,
    Serializer? serializer,
    this.headersProvider,
    String functionPath = '/__odroe/functions',
    this.maxResponseFrameBytes = defaultMaxResponseFrameBytes,
  }) : serializer = serializer ?? Serializer(),
       functionPath = normalizeFunctionPath(functionPath, allowRelative: true) {
    if (maxResponseFrameBytes <= 0) {
      throw ArgumentError.value(
        maxResponseFrameBytes,
        'maxResponseFrameBytes',
        'Must be greater than zero.',
      );
    }
  }

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

  /// Maximum bytes accepted for one typed value or stream response frame.
  ///
  /// This does not cap the cumulative size of a streaming response. Functions
  /// whose output type is [ServerResponse] leave body limits to the caller.
  final int maxResponseFrameBytes;

  /// Calls a value-returning server [function].
  ///
  /// Completing [cancelled] stops the request with [RpcCancelledException].
  Future<O> call<I, O>(
    ServerFunctionRef<I, O> function,
    I data, {
    Future<void>? cancelled,
  }) async {
    final response = await _send(
      function.id,
      function.method,
      data,
      encodeInput: function.encodeInput,
      cancelled: cancelled,
    );
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
      await _readFrame(response, cancelled),
      response.status,
      decode: function.decodeOutput,
    );
  }

  /// Calls a streaming server [function].
  ///
  /// Completing [cancelled] stops request and response streaming with
  /// [RpcCancelledException].
  Future<Stream<T>> stream<I, T>(
    ServerStreamFunctionRef<I, T> function,
    I data, {
    Future<void>? cancelled,
  }) async {
    final response = await _send(
      function.id,
      function.method,
      data,
      encodeInput: function.encodeInput,
      cancelled: cancelled,
    );
    final contentType = response.headers.value('content-type') ?? '';
    if (!contentType.startsWith('application/x-ndjson')) {
      _decodeFrame<Object?>(
        await _readFrame(response, cancelled),
        response.status,
      );
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
    return _decodeResponseFrames(
      stopOnRpcCancellation(response.body, cancelled),
      response.status,
      function.decodeOutput,
    );
  }

  Future<ServerResponse> _send<I>(
    String id,
    HttpMethod method,
    I data, {
    ValueEncoder<I>? encodeInput,
    Future<void>? cancelled,
  }) async {
    final setup = await runUntilRpcCancelled(() async {
      final input = data is NoServerInput
          ? null
          : encodeInput == null
          ? data
          : encodeInput(data);
      return (
        payload: serializer.encodeJson(<String, Object?>{'data': input}),
        headers: await headersProvider?.call(),
      );
    }, cancelled);
    final payload = setup.payload;
    final path = '$functionPath/${Uri.encodeComponent(id)}';
    final headers = _rpcHeaders(baseUri, setup.headers);
    late final ServerRequest request;
    if (method == HttpMethod.get) {
      request = ServerRequest.bytes(
        method: method,
        uri: baseUri
            .resolve(path)
            .replace(queryParameters: <String, String>{'payload': payload}),
        headers: headers,
        cancelled: cancelled,
      );
    } else {
      headers.set('content-type', 'application/json; charset=utf-8');
      request = ServerRequest.bytes(
        method: method,
        uri: baseUri.resolve(path),
        headers: headers,
        body: utf8.encode(payload),
        cancelled: cancelled,
      );
    }
    return runUntilRpcCancelled<ServerResponse>(
      () => transport.send(request),
      cancelled,
    );
  }

  Future<Map<String, Object?>> _readFrame(
    ServerResponse response,
    Future<void>? cancelled,
  ) async {
    late final Uint8List bytes;
    try {
      bytes = await _readResponseFrame(
        stopOnRpcCancellation(response.body, cancelled),
        maxResponseFrameBytes,
      );
    } on _RpcFrameTooLarge {
      _invalidResponse(response.status, _oversizedFrameMessage);
    }
    late final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      _invalidResponse(
        response.status,
        'The server returned invalid RPC text.',
      );
    }
    if (text.isEmpty) {
      _invalidResponse(
        response.status,
        'The server returned an empty RPC response.',
      );
    }
    return _parseFrame(text, response.status);
  }

  String get _oversizedFrameMessage =>
      'The server returned an RPC frame larger than '
      '$maxResponseFrameBytes bytes.';

  Stream<T> _decodeResponseFrames<T>(
    Stream<List<int>> body,
    int status,
    ValueDecoder<T>? decode,
  ) {
    late final StreamController<T> output;
    StreamSubscription<List<int>>? input;
    final builder = BytesBuilder(copy: false);
    var frameLength = 0;
    var previousWasCarriageReturn = false;
    var stopped = false;

    void stop(Object error, StackTrace stackTrace) {
      if (stopped) return;
      final subscription = input;
      input = null;
      stopped = true;
      unawaited(_cancelSubscription(subscription));
      output.addError(error, stackTrace);
      unawaited(output.close());
    }

    void emitFrame() {
      final bytes = builder.takeBytes();
      frameLength = 0;
      if (bytes.isEmpty) return;
      late final String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw _invalidResponseError(
          status,
          'The server returned invalid RPC stream text.',
        );
      }
      final frame = _parseFrame(text, status);
      switch (frame['type']) {
        case 'data':
          output.add(_decodeData(frame['data'], status, decode));
        case 'error':
          _throwRemoteError(frame, status, 'Server stream failed.');
        default:
          _invalidResponse(
            status,
            'The server returned an unknown RPC stream frame.',
          );
      }
    }

    void add(List<int> chunk) {
      if (stopped) return;
      try {
        var start = 0;
        for (var index = 0; index < chunk.length; index++) {
          if (stopped) return;
          final byte = chunk[index];
          if (byte != 0x0a && byte != 0x0d) {
            previousWasCarriageReturn = false;
            frameLength++;
            if (frameLength > maxResponseFrameBytes) {
              throw const _RpcFrameTooLarge();
            }
            continue;
          }
          if (index > start) builder.add(chunk.sublist(start, index));
          start = index + 1;
          if (byte == 0x0a && previousWasCarriageReturn) {
            previousWasCarriageReturn = false;
            continue;
          }
          previousWasCarriageReturn = byte == 0x0d;
          emitFrame();
        }
        if (!stopped && start < chunk.length) {
          builder.add(start == 0 ? chunk : chunk.sublist(start));
        }
      } on _RpcFrameTooLarge catch (_, stackTrace) {
        stop(_invalidResponseError(status, _oversizedFrameMessage), stackTrace);
      } on Object catch (error, stackTrace) {
        stop(error, stackTrace);
      }
    }

    void close() {
      if (stopped) return;
      input = null;
      try {
        emitFrame();
      } on Object catch (error, stackTrace) {
        stop(error, stackTrace);
        return;
      }
      stopped = true;
      unawaited(output.close());
    }

    void listen() {
      if (stopped) return;
      try {
        final subscription = body.listen(
          add,
          onError: stop,
          onDone: close,
          cancelOnError: false,
        );
        input = subscription;
        if (stopped) unawaited(_cancelSubscription(subscription));
      } on Object catch (error, stackTrace) {
        stop(error, stackTrace);
      }
    }

    output = StreamController<T>(
      sync: true,
      onListen: listen,
      onPause: () => input?.pause(),
      onResume: () => input?.resume(),
      onCancel: () {
        final subscription = input;
        input = null;
        stopped = true;
        return _cancelSubscription(subscription);
      },
    );
    return output.stream;
  }

  Object _invalidResponseError(int status, String protocolMessage) {
    if (!_isSuccessful(status)) {
      return RemoteServerException(
        'The server returned HTTP $status without an RPC error frame.',
        status: status,
      );
    }
    return RpcProtocolException(protocolMessage);
  }

  Never _invalidResponse(int status, String protocolMessage) {
    throw _invalidResponseError(status, protocolMessage);
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
    final frame = Map<String, Object?>.from(decoded);
    if (frame['version'] != 1) {
      _invalidResponse(status, 'The server returned an unsupported RPC frame.');
    }
    return frame;
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
        return _decodeData(frame['data'], status, decode);
      case 'redirect':
        final location = frame['location'];
        final redirectStatus = frame['status'];
        if (location is! String || redirectStatus is! int) {
          _invalidResponse(status, 'The server returned an invalid redirect.');
        }
        final parsedLocation = Uri.tryParse(location);
        if (parsedLocation == null || status != redirectStatus) {
          _invalidResponse(status, 'The server returned an invalid redirect.');
        }
        throw Redirect(parsedLocation, status: redirectStatus);
      case 'notFound':
        final message = frame['message'];
        if (status != 404 || (message != null && message is! String)) {
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

  T _decodeData<T>(Object? data, int status, ValueDecoder<T>? decode) {
    try {
      final value = serializer.decode(data);
      return decode == null ? value as T : decode(value);
    } on Object catch (error) {
      if (error is! FormatException &&
          error is! TypeError &&
          error is! RangeError &&
          error is! ArgumentError) {
        rethrow;
      }
      _invalidResponse(
        status,
        'The server returned data that does not match the function output.',
      );
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

Future<Uint8List> _readResponseFrame(Stream<List<int>> body, int maxBytes) {
  final result = Completer<Uint8List>();
  final builder = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? input;
  var length = 0;
  var stopped = false;

  void stop(Object error, StackTrace stackTrace) {
    if (stopped) return;
    final subscription = input;
    input = null;
    stopped = true;
    unawaited(_cancelSubscription(subscription));
    result.completeError(error, stackTrace);
  }

  void add(List<int> chunk) {
    if (stopped) return;
    try {
      length += chunk.length;
      if (length > maxBytes) {
        throw const _RpcFrameTooLarge();
      }
      builder.add(chunk);
    } on Object catch (error, stackTrace) {
      stop(error, stackTrace);
    }
  }

  void close() {
    if (stopped) return;
    stopped = true;
    result.complete(builder.takeBytes());
  }

  try {
    final subscription = body.listen(
      add,
      onError: stop,
      onDone: close,
      cancelOnError: false,
    );
    input = subscription;
    if (stopped) unawaited(_cancelSubscription(subscription));
  } on Object catch (error, stackTrace) {
    stop(error, stackTrace);
  }
  return result.future;
}

Future<void> _cancelSubscription<T>(StreamSubscription<T>? subscription) async {
  try {
    await subscription?.cancel();
  } on Object {
    // Cancellation cleanup cannot replace the RPC result.
  }
}

final class _RpcFrameTooLarge implements Exception {
  const _RpcFrameTooLarge();
}

Future<void> _cancelBody(Stream<List<int>> body) async {
  try {
    final subscription = body.listen(
      null,
      onError: (Object _) {
        // The response is already being rejected by its HTTP or content type.
      },
    );
    await _cancelSubscription(subscription);
  } on Object {
    // Body cleanup cannot replace the protocol or HTTP error.
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

Headers _rpcHeaders(Uri baseUri, Headers? applicationHeaders) {
  final headers = applicationHeaders?.copy() ?? Headers();
  return headers
    ..set('accept', 'application/json, application/x-ndjson')
    ..set('x-odroe-server-function', 'true')
    ..set('origin', _origin(baseUri));
}

bool _isSuccessful(int status) => status >= 200 && status < 300;

String _origin(Uri uri) {
  if (uri.hasAuthority && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return uri.origin;
  }
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
