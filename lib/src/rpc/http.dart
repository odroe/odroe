import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../server/http.dart';
import 'cancellation.dart';
import 'client.dart';

/// Cross-platform HTTP transport backed by package:http.
final class HttpTransport implements RpcTransport {
  /// Default maximum buffered request body size: 10 MiB.
  static const int defaultMaxRequestBodyBytes = 10 * 1024 * 1024;

  /// Creates a transport, optionally reusing an existing HTTP [client].
  HttpTransport({
    http.Client? client,
    int maxRequestBodyBytes = defaultMaxRequestBodyBytes,
  }) : maxRequestBodyBytes = _positiveMaxRequestBodyBytes(maxRequestBodyBytes),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Maximum bytes buffered before one request is sent.
  ///
  /// The limit applies to the request body, not URI query parameters.
  final int maxRequestBodyBytes;

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    var callerCancelled = false;
    final abortTrigger = request.cancelled?.then<void>(
      (_) => callerCancelled = true,
      onError: (Object _, StackTrace _) => callerCancelled = true,
    );
    final outgoing = http.AbortableRequest(
      request.method.wire,
      request.uri,
      abortTrigger: abortTrigger,
    );
    for (final entry in request.headers.entries) {
      if (_framingHeaders.contains(entry.key)) continue;
      outgoing.headers[entry.key] = entry.value.join(', ');
    }
    outgoing.bodyBytes = await runUntilRpcCancelled(
      () => _readBytes(
        stopOnRpcCancellation(request.body, request.cancelled),
        maxRequestBodyBytes,
      ),
      request.cancelled,
    );

    Future<http.StreamedResponse>? pending;
    late final http.StreamedResponse incoming;
    try {
      incoming = await runUntilRpcCancelled(
        () => pending = _client.send(outgoing),
        request.cancelled,
      );
    } on http.RequestAbortedException catch (_, stackTrace) {
      if (callerCancelled) {
        Error.throwWithStackTrace(const RpcCancelledException(), stackTrace);
      }
      rethrow;
    } on RpcCancelledException {
      final lateResponse = pending;
      if (lateResponse != null) {
        unawaited(
          lateResponse.then<void>(
            (response) => _cancelBody(response.stream),
            onError: (Object _, StackTrace _) {},
          ),
        );
      }
      rethrow;
    }
    return ServerResponse(
      status: incoming.statusCode,
      reason: incoming.reasonPhrase,
      headers: Headers.single(incoming.headers),
      body: incoming.stream.handleError((Object error, StackTrace stackTrace) {
        if (callerCancelled) {
          Error.throwWithStackTrace(const RpcCancelledException(), stackTrace);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }, test: (error) => error is http.RequestAbortedException),
    );
  }

  /// Closes the internally owned HTTP client, if any.
  void close() {
    if (_ownsClient) _client.close();
  }
}

const _framingHeaders = <String>{'content-length', 'transfer-encoding'};

int _positiveMaxRequestBodyBytes(int value) {
  if (value <= 0) {
    throw ArgumentError.value(
      value,
      'maxRequestBodyBytes',
      'Must be greater than zero.',
    );
  }
  return value;
}

Future<Uint8List> _readBytes(Stream<List<int>> body, int maxBytes) {
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
        throw PayloadTooLargeException(maxBytes);
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
    // Request body cleanup cannot replace the buffering result.
  }
}

void _cancelBody(Stream<List<int>> body) {
  final subscription = body.listen(
    null,
    onError: (Object _) {
      // Cancellation already won the request.
    },
  );
  unawaited(
    subscription.cancel().then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    ),
  );
}
